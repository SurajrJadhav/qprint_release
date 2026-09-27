package handlers

import (
	"backend/internal/auth"
	"backend/internal/database"
	"backend/internal/models"
	"backend/internal/notifications"
	"backend/internal/payment"
	"backend/internal/utils"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"strings"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
)

var razorpayClient *payment.RazorpayClient

func init() {
	var err error
	razorpayClient, err = payment.NewRazorpayClient()
	if err != nil {
		fmt.Printf("Warning: Failed to initialize Razorpay client: %v\n", err)
		fmt.Println("Payment features will be disabled. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET to enable.")
	}
}

// CalculateCost calculates the cost before payment (supports multiple files)
func CalculateCost(w http.ResponseWriter, r *http.Request) {
	// Limit total form size to 100MB (for batch uploads)
	const maxGroupSize = 100 << 20 // 100MB total
	const maxFileSize = 20 << 20   // 20MB per file
	r.ParseMultipartForm(maxGroupSize)

	// Get copies, color_mode, print_mode, and optional shop_id (for queue pricing)
	copiesStr := r.FormValue("copies")
	copies := 1
	if copiesStr != "" {
		if c, err := strconv.Atoi(copiesStr); err == nil && c > 0 {
			copies = c
		}
	}
	if copies > 1000 {
		http.Error(w, "Copies cannot exceed 1000", http.StatusBadRequest)
		return
	}
	colorMode := r.FormValue("color_mode")
	if colorMode == "" {
		colorMode = "bw"
	}
	printMode := r.FormValue("print_mode")
	if printMode == "" {
		printMode = "single"
	}
	// Normalize print_mode to prevent injection into downstream logic
	if printMode != "single" && printMode != "double" {
		printMode = "single"
	}
	var shopID *int
	if shopIDStr := strings.TrimSpace(r.FormValue("shop_id")); shopIDStr != "" {
		if sid, err := strconv.Atoi(shopIDStr); err == nil && sid > 0 && sid <= 999999999 {
			shopID = &sid
		}
	}

	// Support both single file ("file") and multiple files ("files[]")
	var fileHeaders []*multipart.FileHeader
	if r.MultipartForm != nil {
		// Try multiple files first
		if files, ok := r.MultipartForm.File["files[]"]; ok && len(files) > 0 {
			fileHeaders = files
		} else if file, ok := r.MultipartForm.File["file"]; ok && len(file) > 0 {
			// Fallback to single file for backward compatibility
			fileHeaders = file
		}
	}

	// If no files found, try the old way
	if len(fileHeaders) == 0 {
		file, handler, err := r.FormFile("file")
		if err != nil {
			http.Error(w, "No files provided", http.StatusBadRequest)
			return
		}
		file.Close()
		fileHeaders = append(fileHeaders, handler)
	}

	if len(fileHeaders) == 0 {
		http.Error(w, "No files provided", http.StatusBadRequest)
		return
	}

	// Validate total group size and individual file sizes
	totalSize := int64(0)
	allowedExtensions := map[string]bool{
		".pdf": true, ".png": true, ".jpg": true, ".jpeg": true,
		".doc": true, ".docx": true, ".ppt": true, ".pptx": true,
	}
	supportedMsg := "Supported: PDF, images (PNG/JPG/JPEG), Word (DOC/DOCX), PowerPoint (PPT/PPTX)"

	for _, handler := range fileHeaders {
		// Validate individual file size
		if handler.Size > maxFileSize {
			http.Error(w, fmt.Sprintf("File '%s' exceeds maximum limit of 20MB per file", handler.Filename), http.StatusBadRequest)
			return
		}

		// Validate file extension
		ext := filepath.Ext(handler.Filename)
		if !allowedExtensions[ext] {
			http.Error(w, fmt.Sprintf("File '%s': %s", handler.Filename, supportedMsg), http.StatusBadRequest)
			return
		}

		totalSize += handler.Size
	}

	// Validate total group size
	if totalSize > maxGroupSize {
		http.Error(w, fmt.Sprintf("Total file size (%.2fMB) exceeds maximum limit of 100MB", float64(totalSize)/(1024*1024)), http.StatusBadRequest)
		return
	}

	// Process all files and calculate total pages
	totalPages := 0
	fileDetails := []map[string]interface{}{}

	for _, handler := range fileHeaders {
		file, err := handler.Open()
		if err != nil {
			http.Error(w, fmt.Sprintf("Error opening file '%s': %v", handler.Filename, err), http.StatusBadRequest)
			return
		}

		// Read file bytes
		fileBytes, err := io.ReadAll(file)
		file.Close()
		if err != nil {
			http.Error(w, fmt.Sprintf("Error reading file '%s': %v", handler.Filename, err), http.StatusInternalServerError)
			return
		}

		ext := filepath.Ext(handler.Filename)
		if err := utils.ValidateImageBytes(fileBytes, ext); err != nil {
			http.Error(w, fmt.Sprintf("File '%s': %v", handler.Filename, err), http.StatusBadRequest)
			return
		}

		// Count pages: PDF = count; PPTX = slides; DOCX = estimated pages; images, DOC, PPT = 1
		var numPages int
		switch ext {
		case ".pdf":
			numPages, err = utils.CountPDFPagesFromReader(bytes.NewReader(fileBytes))
			if err != nil {
				if errors.Is(err, utils.ErrPageCountNotAvailable) {
					http.Error(w, fmt.Sprintf("File '%s': %s", handler.Filename, utils.PageCountNotAvailableMessage), http.StatusBadRequest)
				} else {
					http.Error(w, fmt.Sprintf("File '%s': PDF appears corrupted or invalid; please use a valid PDF file", handler.Filename), http.StatusBadRequest)
				}
				return
			}
		case ".pptx":
			numPages, err = utils.CountPPTXSlides(bytes.NewReader(fileBytes))
			if err != nil {
				if errors.Is(err, utils.ErrPageCountNotAvailable) {
					http.Error(w, fmt.Sprintf("File '%s': %s", handler.Filename, utils.PageCountNotAvailableMessage), http.StatusBadRequest)
				} else {
					http.Error(w, fmt.Sprintf("File '%s': PowerPoint file appears corrupted or invalid", handler.Filename), http.StatusBadRequest)
				}
				return
			}
			if numPages < 1 {
				numPages = 1
			}
		case ".docx":
			numPages, err = utils.CountDOCXPages(bytes.NewReader(fileBytes))
			if err != nil {
				if errors.Is(err, utils.ErrPageCountNotAvailable) {
					http.Error(w, fmt.Sprintf("File '%s': %s", handler.Filename, utils.PageCountNotAvailableMessage), http.StatusBadRequest)
				} else {
					http.Error(w, fmt.Sprintf("File '%s': Word file appears corrupted or invalid", handler.Filename), http.StatusBadRequest)
				}
				return
			}
			if numPages < 1 {
				numPages = 1
			}
		case ".ppt":
			numPages, err = utils.CountPPTSlides(bytes.NewReader(fileBytes))
			if err != nil {
				if errors.Is(err, utils.ErrPageCountNotAvailable) {
					http.Error(w, fmt.Sprintf("File '%s': %s", handler.Filename, utils.PageCountNotAvailableMessage), http.StatusBadRequest)
				} else {
					http.Error(w, fmt.Sprintf("File '%s': PowerPoint file appears corrupted or invalid", handler.Filename), http.StatusBadRequest)
				}
				return
			}
			if numPages < 1 {
				numPages = 1
			}
		case ".doc":
			numPages, err = utils.CountDOCPages(bytes.NewReader(fileBytes))
			if err != nil {
				if errors.Is(err, utils.ErrPageCountNotAvailable) {
					http.Error(w, fmt.Sprintf("File '%s': %s", handler.Filename, utils.PageCountNotAvailableMessage), http.StatusBadRequest)
				} else {
					http.Error(w, fmt.Sprintf("File '%s': Word file appears corrupted or invalid", handler.Filename), http.StatusBadRequest)
				}
				return
			}
			if numPages < 1 {
				numPages = 1
			}
		default:
			numPages = 1 // images
		}

		totalPages += numPages
		fileCost := ComputeOrderCost(numPages, copies, colorMode, printMode, shopID)

		fileDetails = append(fileDetails, map[string]interface{}{
			"filename":   handler.Filename,
			"size":       handler.Size,
			"pages":      numPages,
			"cost":       fileCost,
			"size_mb":    fmt.Sprintf("%.2f", float64(handler.Size)/(1024*1024)),
		})
	}

	// Calculate total cost (platform or shop rates; double-sided factor when print_mode is "double")
	totalCost := ComputeOrderCost(totalPages, copies, colorMode, printMode, shopID)
	// Effective cost per page for response (display only). Double-sided factor is shopkeeper-set only.
	costPerPage := utils.GetCostPerPageForMode(colorMode)
	if shopID != nil {
		rateBW, rateColor, factorDouble := getShopPricing(*shopID)
		if strings.EqualFold(colorMode, "color") && rateColor != nil {
			costPerPage = *rateColor
		} else if rateBW != nil {
			costPerPage = *rateBW
		}
		if strings.EqualFold(printMode, "double") && factorDouble != nil {
			costPerPage *= *factorDouble
		}
	}

	response := map[string]interface{}{
		"num_pages":     totalPages,
		"copies":        copies,
		"color_mode":    colorMode,
		"print_mode":    printMode,
		"total_cost":    totalCost,
		"cost_per_page": costPerPage,
		"file_count":   len(fileHeaders),
		"files":        fileDetails,
		"total_size_mb": fmt.Sprintf("%.2f", float64(totalSize)/(1024*1024)),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// CalculateCostFromPagesRequest is the JSON body for POST /calculate-cost-from-pages.
type CalculateCostFromPagesRequest struct {
	TotalPages int    `json:"total_pages"`
	Copies     int    `json:"copies"`
	PrintMode  string `json:"print_mode"`
	ColorMode  string `json:"color_mode"`
	ShopID     *int   `json:"shop_id,omitempty"`
}

// CalculateCostFromPages returns cost for a given total page count (no file upload).
// Used when the client already has page counts (e.g. after a previous calculate-cost) and only
// shop or print type changed, to avoid re-uploading files.
func CalculateCostFromPages(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Content-Type") != "" && !strings.Contains(r.Header.Get("Content-Type"), "application/json") {
		http.Error(w, "Content-Type must be application/json", http.StatusBadRequest)
		return
	}
	var req CalculateCostFromPagesRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON body", http.StatusBadRequest)
		return
	}
	if req.TotalPages < 1 {
		http.Error(w, "total_pages must be at least 1", http.StatusBadRequest)
		return
	}
	if req.Copies < 1 {
		req.Copies = 1
	}
	if req.Copies > 1000 {
		http.Error(w, "copies cannot exceed 1000", http.StatusBadRequest)
		return
	}
	if req.ColorMode == "" {
		req.ColorMode = "bw"
	}
	if req.PrintMode == "" {
		req.PrintMode = "single"
	}
	if req.PrintMode != "single" && req.PrintMode != "double" {
		req.PrintMode = "single"
	}
	var shopID *int
	if req.ShopID != nil && *req.ShopID > 0 && *req.ShopID <= 999999999 {
		shopID = req.ShopID
	}

	totalCost := ComputeOrderCost(req.TotalPages, req.Copies, req.ColorMode, req.PrintMode, shopID)
	costPerPage := utils.GetCostPerPageForMode(req.ColorMode)
	if shopID != nil {
		rateBW, rateColor, factorDouble := getShopPricing(*shopID)
		if strings.EqualFold(req.ColorMode, "color") && rateColor != nil {
			costPerPage = *rateColor
		} else if rateBW != nil {
			costPerPage = *rateBW
		}
		if strings.EqualFold(req.PrintMode, "double") && factorDouble != nil {
			costPerPage *= *factorDouble
		}
	}

	response := map[string]interface{}{
		"num_pages":     req.TotalPages,
		"total_pages":   req.TotalPages,
		"copies":        req.Copies,
		"color_mode":    req.ColorMode,
		"print_mode":    req.PrintMode,
		"total_cost":    totalCost,
		"cost_per_page": costPerPage,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// CreatePaymentOrder creates a Razorpay payment order with shopkeeper tracking
func CreatePaymentOrder(w http.ResponseWriter, r *http.Request) {
	// Check if we're in test mode (allow bypassing Razorpay)
	testMode := os.Getenv("TEST_MODE") == "true" || os.Getenv("ENVIRONMENT") == "development"
	
	if razorpayClient == nil && !testMode {
		http.Error(w, "Payment service not configured", http.StatusServiceUnavailable)
		return
	}

	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req models.CreatePaymentOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Validate amount: reject zero, negative, NaN, Inf, and cap max to prevent abuse
	if req.Amount != req.Amount || req.Amount <= 0 || req.Amount > 100000 {
		http.Error(w, "Amount must be greater than 0 and at most 100000", http.StatusBadRequest)
		return
	}
	if req.WalletAmount != nil {
		wa := *req.WalletAmount
		if wa != wa || wa < 0 {
			http.Error(w, "Invalid wallet amount", http.StatusBadRequest)
			return
		}
	}

	// Validate print type
	if req.PrintType != "private" && req.PrintType != "queue" {
		http.Error(w, "Print type must be 'private' or 'queue'", http.StatusBadRequest)
		return
	}

	// For queue prints, shopkeeper_id is required
	if req.PrintType == "queue" {
		if req.ShopkeeperID == nil {
			http.Error(w, "shopkeeper_id is required for queue prints", http.StatusBadRequest)
			return
		}

		// Verify shopkeeper exists
		var shopExists bool
		err := database.DB.QueryRow(context.Background(),
			"SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND role = 'shopkeeper')",
			*req.ShopkeeperID).Scan(&shopExists)
		if err != nil || !shopExists {
			http.Error(w, "Shopkeeper not found", http.StatusNotFound)
			return
		}
	}

	// Set default platform commission (0% = no commission)
	// Commission is optional - set to 0 by default
	platformCommission := 0.0
	if req.PlatformCommission != nil {
		platformCommission = *req.PlatformCommission
		if platformCommission < 0 || platformCommission > 1 {
			platformCommission = 0.0 // Default to 0% (no commission)
		}
	}

	// Calculate shopkeeper amount
	var shopkeeperAmount *float64
	if req.PrintType == "queue" && req.ShopkeeperID != nil {
		amount := payment.CalculateShopkeeperAmount(req.Amount, platformCommission)
		shopkeeperAmount = &amount
	}

	var walletBalance float64
	if req.UseWallet {
		_ = database.DB.QueryRow(context.Background(),
			"SELECT COALESCE(wallet_balance, 0) FROM users WHERE id = $1", claims.UserID).Scan(&walletBalance)
	}
	walletToUse := 0.0
	if req.UseWallet && walletBalance > 0 {
		if req.WalletAmount != nil && *req.WalletAmount > 0 {
			walletToUse = *req.WalletAmount
			if walletToUse > walletBalance {
				walletToUse = walletBalance
			}
			if walletToUse > req.Amount {
				walletToUse = req.Amount
			}
		} else {
			if walletBalance >= req.Amount {
				walletToUse = req.Amount
			} else {
				walletToUse = walletBalance
			}
		}
	}

	paymentMethod := "razorpay"
	orderStatus := "pending"
	var paymentOrderID int
	var razorpayOrderID string
	var keyID string
	expiresAt := payment.GetExpiryTime()

	// Full wallet payment
	if walletToUse >= req.Amount {
		paymentMethod = "wallet"
		orderStatus = "paid"
		razorpayOrderID = fmt.Sprintf("wallet_%d_%d", claims.UserID, time.Now().UnixNano())
		keyID = ""

		tx, err := database.DB.Begin(context.Background())
		if err != nil {
			log.Printf("CreatePaymentOrder: begin tx: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}
		defer tx.Rollback(context.Background())

		var balanceAfter float64
		err = tx.QueryRow(context.Background(),
			`UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) - $1 WHERE id = $2 AND COALESCE(wallet_balance, 0) >= $1 RETURNING wallet_balance`,
			req.Amount, claims.UserID).Scan(&balanceAfter)
		if err != nil {
			http.Error(w, "Insufficient wallet balance", http.StatusBadRequest)
			return
		}
		balanceBefore := balanceAfter + req.Amount

		err = tx.QueryRow(context.Background(),
			`INSERT INTO payment_orders 
			 (user_id, order_id, amount, status, payment_method, wallet_amount, shopkeeper_id, platform_commission, shopkeeper_amount,
			  copies, print_mode, color_mode, paper_size, print_type, comment, expires_at)
			 VALUES ($1, $2, $3, 'paid', 'wallet', $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
			 RETURNING id`,
			claims.UserID, razorpayOrderID, req.Amount, req.Amount,
			req.ShopkeeperID, platformCommission, shopkeeperAmount,
			req.Copies, req.PrintMode, req.ColorMode, req.PaperSize, req.PrintType, req.Comment, expiresAt).Scan(&paymentOrderID)
		if err != nil {
			log.Printf("CreatePaymentOrder: insert order: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}

		_, err = tx.Exec(context.Background(),
			`INSERT INTO wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, payment_order_id, status)
			 VALUES ($1, 'payment', $2, $3, $4, $5, 'completed')`,
			claims.UserID, req.Amount, balanceBefore, balanceAfter, paymentOrderID)
		if err != nil {
			log.Printf("CreatePaymentOrder: wallet tx: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}

		if req.ShopkeeperID != nil && shopkeeperAmount != nil && *shopkeeperAmount > 0 {
			_, _ = tx.Exec(context.Background(),
				`INSERT INTO shopkeeper_payouts (shopkeeper_id, payment_order_id, amount, status)
				 VALUES ($1, $2, $3, 'pending')
				 ON CONFLICT (shopkeeper_id, payment_order_id) DO NOTHING`,
				*req.ShopkeeperID, paymentOrderID, *shopkeeperAmount)
		}

		if err = tx.Commit(context.Background()); err != nil {
			log.Printf("CreatePaymentOrder: commit: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}

		response := map[string]interface{}{
			"id":               paymentOrderID,
			"order_id":         razorpayOrderID,
			"amount":           req.Amount,
			"status":           "paid",
			"payment_method":   "wallet",
			"wallet_amount":    req.Amount,
			"razorpay_amount":  0.0,
			"skip_payment":     true,
			"shopkeeper_id":    req.ShopkeeperID,
			"shopkeeper_amount": shopkeeperAmount,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
		return
	}

	// Hybrid: deduct wallet part, create Razorpay for rest
	if walletToUse > 0 {
		paymentMethod = "hybrid"
		razorpayAmount := req.Amount - walletToUse

		tx, err := database.DB.Begin(context.Background())
		if err != nil {
			log.Printf("CreatePaymentOrder: hybrid begin: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}
		defer tx.Rollback(context.Background())

		var balanceAfter float64
		err = tx.QueryRow(context.Background(),
			`UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) - $1 WHERE id = $2 AND COALESCE(wallet_balance, 0) >= $1 RETURNING wallet_balance`,
			walletToUse, claims.UserID).Scan(&balanceAfter)
		if err != nil {
			http.Error(w, "Insufficient wallet balance", http.StatusBadRequest)
			return
		}
		balanceBefore := balanceAfter + walletToUse

		// Create Razorpay order for remainder
		receipt := payment.GenerateReceipt(claims.UserID, time.Now().Unix())
		notes := map[string]string{
			"user_id":       fmt.Sprintf("%d", claims.UserID),
			"print_type":    req.PrintType,
			"platform":      "qprint",
			"wallet_amount": fmt.Sprintf("%.2f", walletToUse),
		}
		if req.ShopkeeperID != nil {
			notes["shopkeeper_id"] = fmt.Sprintf("%d", *req.ShopkeeperID)
		}
		razorpayOrder, err := razorpayClient.CreateOrder(razorpayAmount, receipt, notes)
		if err != nil {
			log.Printf("CreatePaymentOrder: hybrid Razorpay: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}
		razorpayOrderID = razorpayOrder.ID
		keyID = razorpayClient.KeyID

		err = tx.QueryRow(context.Background(),
			`INSERT INTO payment_orders 
			 (user_id, order_id, amount, status, payment_method, wallet_amount, shopkeeper_id, platform_commission, shopkeeper_amount,
			  copies, print_mode, color_mode, paper_size, print_type, comment, expires_at)
			 VALUES ($1, $2, $3, 'pending', 'hybrid', $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
			 RETURNING id`,
			claims.UserID, razorpayOrderID, req.Amount, walletToUse,
			req.ShopkeeperID, platformCommission, shopkeeperAmount,
			req.Copies, req.PrintMode, req.ColorMode, req.PaperSize, req.PrintType, req.Comment, expiresAt).Scan(&paymentOrderID)
		if err != nil {
			log.Printf("CreatePaymentOrder: hybrid insert: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}

		_, err = tx.Exec(context.Background(),
			`INSERT INTO wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, payment_order_id, status)
			 VALUES ($1, 'payment', $2, $3, $4, $5, 'completed')`,
			claims.UserID, walletToUse, balanceBefore, balanceAfter, paymentOrderID)
		if err != nil {
			log.Printf("CreatePaymentOrder: hybrid wallet tx: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}

		if err = tx.Commit(context.Background()); err != nil {
			log.Printf("CreatePaymentOrder: hybrid commit: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}

		response := map[string]interface{}{
			"id":               paymentOrderID,
			"order_id":         razorpayOrderID,
			"amount":           req.Amount,
			"status":           "pending",
			"payment_method":   "hybrid",
			"wallet_amount":    walletToUse,
			"razorpay_amount":  razorpayAmount,
			"key_id":           keyID,
			"shopkeeper_id":    req.ShopkeeperID,
			"shopkeeper_amount": shopkeeperAmount,
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
		return
	}

	// Razorpay-only flow
	if testMode && razorpayClient == nil {
		razorpayOrderID = fmt.Sprintf("test_order_%d_%d", claims.UserID, time.Now().Unix())
		keyID = "test_key_id"
		orderStatus = "paid"
	} else {
		receipt := payment.GenerateReceipt(claims.UserID, time.Now().Unix())
		notes := map[string]string{
			"user_id":    fmt.Sprintf("%d", claims.UserID),
			"print_type": req.PrintType,
			"platform":   "qprint",
		}
		if req.ShopkeeperID != nil {
			notes["shopkeeper_id"] = fmt.Sprintf("%d", *req.ShopkeeperID)
		}
		razorpayOrder, err := razorpayClient.CreateOrder(req.Amount, receipt, notes)
		if err != nil {
			log.Printf("CreatePaymentOrder: Razorpay error: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}
		razorpayOrderID = razorpayOrder.ID
		keyID = razorpayClient.KeyID
	}

	err := database.DB.QueryRow(context.Background(),
		`INSERT INTO payment_orders 
		 (user_id, order_id, amount, status, payment_method, wallet_amount, shopkeeper_id, platform_commission, shopkeeper_amount,
		  copies, print_mode, color_mode, paper_size, print_type, comment, expires_at)
		 VALUES ($1, $2, $3, $4, 'razorpay', 0, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
		 RETURNING id`,
		claims.UserID, razorpayOrderID, req.Amount, orderStatus,
		req.ShopkeeperID, platformCommission, shopkeeperAmount,
		req.Copies, req.PrintMode, req.ColorMode, req.PaperSize, req.PrintType, req.Comment, expiresAt).Scan(&paymentOrderID)

	if err != nil {
		log.Printf("CreatePaymentOrder: database error: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	if testMode && razorpayClient == nil && orderStatus == "paid" && req.ShopkeeperID != nil && shopkeeperAmount != nil && *shopkeeperAmount > 0 {
		_, _ = database.DB.Exec(context.Background(),
			`INSERT INTO shopkeeper_payouts (shopkeeper_id, payment_order_id, amount, status)
			 VALUES ($1, $2, $3, 'pending')
			 ON CONFLICT (shopkeeper_id, payment_order_id) DO NOTHING`,
			*req.ShopkeeperID, paymentOrderID, *shopkeeperAmount)
	}

	response := map[string]interface{}{
		"id":                paymentOrderID,
		"order_id":          razorpayOrderID,
		"amount":            req.Amount,
		"status":            orderStatus,
		"payment_method":   paymentMethod,
		"wallet_amount":     0.0,
		"razorpay_amount":   req.Amount,
		"key_id":            keyID,
		"shopkeeper_id":     req.ShopkeeperID,
		"shopkeeper_amount": shopkeeperAmount,
	}
	if testMode && razorpayClient == nil {
		response["test_mode"] = true
		response["skip_payment"] = true
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// PaymentWebhook handles Razorpay webhook events
func PaymentWebhook(w http.ResponseWriter, r *http.Request) {
	if razorpayClient == nil {
		http.Error(w, "Payment service not configured", http.StatusServiceUnavailable)
		return
	}

	// Fail fast if webhook secret not configured (do not process any webhook without verification)
	if os.Getenv("RAZORPAY_WEBHOOK_SECRET") == "" {
		log.Printf("PaymentWebhook: RAZORPAY_WEBHOOK_SECRET not set, rejecting webhook")
		http.Error(w, "Webhook not configured", http.StatusServiceUnavailable)
		return
	}

	// Limit webhook body size to prevent DoS (Razorpay payloads are typically small)
	const maxWebhookBody = 256 * 1024 // 256KB
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxWebhookBody))
	if err != nil {
		if strings.Contains(err.Error(), "request body too large") {
			http.Error(w, "Payload too large", http.StatusRequestEntityTooLarge)
			return
		}
		log.Printf("PaymentWebhook: read body: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	// Get signature from header
	signature := r.Header.Get("X-Razorpay-Signature")
	if signature == "" {
		http.Error(w, "Missing signature", http.StatusBadRequest)
		return
	}

	// Verify signature
	if !razorpayClient.VerifyWebhookSignature(string(body), signature) {
		log.Printf("PaymentWebhook: invalid signature (rejected)")
		http.Error(w, "Invalid signature", http.StatusUnauthorized)
		return
	}

	// Do not log raw payload or payment/order IDs in production (sensitive data)
	debugLog := os.Getenv("LOG_LEVEL") == "debug" || os.Getenv("DEBUG") == "true"
	if debugLog {
		log.Printf("PaymentWebhook: payload length=%d", len(body))
	}

	// Parse webhook event - Razorpay webhook structure
	var webhookEvent struct {
		Event   string `json:"event"`
		Payload struct {
			Payment struct {
				Entity struct {
					ID      string `json:"id"`
					OrderID string `json:"order_id"`
					Status  string `json:"status"`
					Amount  int64  `json:"amount"`
				} `json:"entity"`
			} `json:"payment"`
			Order struct {
				Entity struct {
					ID     string `json:"id"`
					Status string `json:"status"`
				} `json:"entity"`
			} `json:"order"`
		} `json:"payload"`
	}

	if err := json.Unmarshal(body, &webhookEvent); err != nil {
		log.Printf("PaymentWebhook: parse error: %v", err)
		http.Error(w, "Invalid webhook payload", http.StatusBadRequest)
		return
	}

	if debugLog {
		log.Printf("PaymentWebhook: event=%s", webhookEvent.Event)
	}

	// Handle payment.captured event
	if webhookEvent.Event == "payment.captured" {
		paymentID := webhookEvent.Payload.Payment.Entity.ID
		orderID := webhookEvent.Payload.Payment.Entity.OrderID
		amountPaise := webhookEvent.Payload.Payment.Entity.Amount
		amount := float64(amountPaise) / 100.0

		// Wallet top-up: claim row atomically to prevent double-credit on webhook replay/concurrency
		tx, txErr := database.DB.Begin(context.Background())
		if txErr != nil {
			log.Printf("PaymentWebhook: topup begin tx: %v", txErr)
			http.Error(w, "An error occurred.", http.StatusInternalServerError)
			return
		}
		defer tx.Rollback(context.Background())
		var topupUserID int
		var topupAmount float64
		err = tx.QueryRow(context.Background(),
			`UPDATE wallet_topup_orders SET payment_id = $1, status = 'completed' WHERE order_id = $2 AND status = 'pending' RETURNING user_id, amount`,
			paymentID, orderID).Scan(&topupUserID, &topupAmount)
		if err == nil {
			// We claimed the row; credit wallet and insert audit record
			var balanceAfter float64
			err = tx.QueryRow(context.Background(),
				`UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + $1 WHERE id = $2 RETURNING wallet_balance`,
				topupAmount, topupUserID).Scan(&balanceAfter)
			if err != nil {
				log.Printf("PaymentWebhook: topup credit: %v", err)
				http.Error(w, "An error occurred.", http.StatusInternalServerError)
				return
			}
			balanceBefore := balanceAfter - topupAmount
			_, err = tx.Exec(context.Background(),
				`INSERT INTO wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, razorpay_payment_id, status)
				 VALUES ($1, 'topup', $2, $3, $4, $5, 'completed')`,
				topupUserID, topupAmount, balanceBefore, balanceAfter, paymentID)
			if err != nil {
				log.Printf("PaymentWebhook: topup insert tx: %v", err)
				http.Error(w, "An error occurred.", http.StatusInternalServerError)
				return
			}
			if err = tx.Commit(context.Background()); err != nil {
				log.Printf("PaymentWebhook: topup commit: %v", err)
				http.Error(w, "An error occurred.", http.StatusInternalServerError)
				return
			}
			TryCreditReferral(topupUserID)
			notifications.SendToUser(topupUserID, "Wallet topped up", notifications.FormatAmount(topupAmount)+" added to your wallet.", map[string]string{"type": "wallet_topup"})
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("OK"))
			return
		}
		tx.Rollback(context.Background())
		// Not a top-up or already processed; fall through to regular payment order

		// Regular payment order
		result, err := database.DB.Exec(context.Background(),
			`UPDATE payment_orders 
			 SET payment_id = $1, status = 'paid', paid_at = NOW()
			 WHERE order_id = $2 AND status = 'pending'`,
			paymentID, orderID)

		if err != nil {
			log.Printf("PaymentWebhook: update payment order: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}

		_ = amount
		rowsAffected := result.RowsAffected()
		if debugLog {
			log.Printf("PaymentWebhook: payment.captured rows=%d", rowsAffected)
		}

		// Referral: try to credit referrer if this is referee's first successful print payment
		var orderUserID int
		if database.DB.QueryRow(context.Background(), "SELECT user_id FROM payment_orders WHERE order_id = $1", orderID).Scan(&orderUserID) == nil && orderUserID > 0 {
			TryCreditReferral(orderUserID)
			notifications.SendToUser(orderUserID, "Payment successful", "Your print order payment was successful.", map[string]string{"type": "payment_success", "order_id": orderID})
		}

		// Create shopkeeper payout record if applicable
		var shopkeeperID *int
		var shopkeeperAmount *float64
		err = database.DB.QueryRow(context.Background(),
			`SELECT shopkeeper_id, shopkeeper_amount 
			 FROM payment_orders WHERE order_id = $1`,
			orderID).Scan(&shopkeeperID, &shopkeeperAmount)

		if err == nil && shopkeeperID != nil && shopkeeperAmount != nil && *shopkeeperAmount > 0 {
			var paymentOrderID int
			err = database.DB.QueryRow(context.Background(),
				"SELECT id FROM payment_orders WHERE order_id = $1", orderID).Scan(&paymentOrderID)
			if err == nil {
				database.DB.Exec(context.Background(),
					`INSERT INTO shopkeeper_payouts (shopkeeper_id, payment_order_id, amount, status)
					 VALUES ($1, $2, $3, 'pending')
					 ON CONFLICT (shopkeeper_id, payment_order_id) DO NOTHING`,
					*shopkeeperID, paymentOrderID, *shopkeeperAmount)
			}
		}
	}

	// Handle payment.failed event
	if webhookEvent.Event == "payment.failed" {
		orderID := webhookEvent.Payload.Payment.Entity.OrderID
		_, err = database.DB.Exec(context.Background(),
			`UPDATE payment_orders SET status = 'failed' WHERE order_id = $1 AND status = 'pending'`,
			orderID)
		if err != nil {
			log.Printf("PaymentWebhook: update failed payment: %v", err)
		}
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

// GetPaymentStatus returns the status of a payment order
func GetPaymentStatus(w http.ResponseWriter, r *http.Request) {
	orderID := chi.URLParam(r, "orderId")
	if orderID == "" {
		http.Error(w, "Order ID required", http.StatusBadRequest)
		return
	}

	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Get payment order (verify it belongs to user)
	var paymentOrder models.PaymentOrder
	err := database.DB.QueryRow(context.Background(),
		`SELECT id, user_id, order_id, payment_id, amount, status, shopkeeper_id, 
		 shopkeeper_amount, created_at, paid_at, expires_at
		 FROM payment_orders WHERE order_id = $1 AND user_id = $2`,
		orderID, claims.UserID).Scan(
		&paymentOrder.ID, &paymentOrder.UserID, &paymentOrder.OrderID,
		&paymentOrder.PaymentID, &paymentOrder.Amount, &paymentOrder.Status,
		&paymentOrder.ShopkeeperID, &paymentOrder.ShopkeeperAmount,
		&paymentOrder.CreatedAt, &paymentOrder.PaidAt, &paymentOrder.ExpiresAt)

	if err != nil {
		http.Error(w, "Payment order not found", http.StatusNotFound)
		return
	}

	// Check if expired
	if paymentOrder.Status == "pending" && paymentOrder.ExpiresAt != nil {
		if time.Now().After(*paymentOrder.ExpiresAt) {
			// Update status to expired
			database.DB.Exec(context.Background(),
				"UPDATE payment_orders SET status = 'expired' WHERE id = $1",
				paymentOrder.ID)
			paymentOrder.Status = "expired"
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(paymentOrder)
}

// GetShopkeeperPayouts returns pending payouts for a shopkeeper
func GetShopkeeperPayouts(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Verify user is a shopkeeper
	var role string
	err := database.DB.QueryRow(context.Background(),
		"SELECT role FROM users WHERE id = $1", claims.UserID).Scan(&role)
	if err != nil || role != "shopkeeper" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	rows, err := database.DB.Query(context.Background(),
		`SELECT sp.id, sp.shopkeeper_id, sp.payment_order_id, sp.amount, sp.status,
		 sp.payout_method, sp.payout_reference, sp.paid_at, sp.created_at,
		 po.order_id, po.amount as total_amount
		 FROM shopkeeper_payouts sp
		 JOIN payment_orders po ON sp.payment_order_id = po.id
		 WHERE sp.shopkeeper_id = $1
		 ORDER BY sp.created_at DESC`,
		claims.UserID)

	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var payouts []map[string]interface{}
	for rows.Next() {
		var payout models.ShopkeeperPayout
		var totalAmount float64
		var orderID string
		if err := rows.Scan(
			&payout.ID, &payout.ShopkeeperID, &payout.PaymentOrderID,
			&payout.Amount, &payout.Status, &payout.PayoutMethod,
			&payout.PayoutReference, &payout.PaidAt, &payout.CreatedAt,
			&orderID, &totalAmount); err != nil {
			continue
		}

		payouts = append(payouts, map[string]interface{}{
			"id":               payout.ID,
			"payment_order_id": payout.PaymentOrderID,
			"order_id":         orderID,
			"amount":           payout.Amount,
			"total_amount":     totalAmount,
			"status":           payout.Status,
			"payout_method":    payout.PayoutMethod,
			"payout_reference": payout.PayoutReference,
			"paid_at":          payout.PaidAt,
			"created_at":       payout.CreatedAt,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"payouts": payouts})
}
