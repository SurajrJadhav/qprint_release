package handlers

import (
	"backend/internal/auth"
	"backend/internal/database"
	"backend/internal/notifications"
	"backend/internal/payment"
	"backend/internal/shopkeeperstream"
	"backend/internal/storage"
	"backend/internal/utils"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"math"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// isTestMode returns true only when explicitly in development/test; false in production. Logs when used.
func isTestMode() bool {
	env := os.Getenv("ENVIRONMENT")
	testMode := os.Getenv("TEST_MODE") == "true"
	if env == "production" {
		return false
	}
	ok := testMode || env == "development"
	if ok {
		// Log test mode usage for audit
		fmt.Printf("SECURITY: Test mode active (ENVIRONMENT=%s, TEST_MODE=%s)\n", env, os.Getenv("TEST_MODE"))
	}
	return ok
}

var fileStorage storage.Storage

// InitStorage initializes the storage backend
// Must be called after environment variables are loaded
func InitStorage() {
	var err error
	fileStorage, err = storage.NewStorage()
	if err != nil {
		// Log error but continue - will use local storage as fallback
		fmt.Printf("Warning: Failed to initialize storage, using local storage: %v\n", err)
		fileStorage = storage.NewLocalStorage()
	}
}

// init() - Initialize with local storage as fallback (will be re-initialized in main)
func init() {
	// Use local storage as temporary fallback
	// Will be properly initialized in main() after .env is loaded
	fileStorage = storage.NewLocalStorage()
}

const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
const maxFilenameLen = 200

// sanitizeFilename removes path traversal and unsafe chars; keeps extension and short safe name.
func sanitizeFilename(name string) string {
	base := filepath.Base(name)
	base = strings.TrimSpace(base)
	if base == "" || base == "." || base == ".." {
		base = "file"
	}
	// Remove any path components that might have slipped through
	base = strings.ReplaceAll(base, "..", "")
	// Allow alphanumeric, dash, underscore, dot
	safe := regexp.MustCompile(`[^a-zA-Z0-9._-]`).ReplaceAllString(base, "_")
	if len(safe) > maxFilenameLen {
		ext := filepath.Ext(safe)
		safe = safe[:maxFilenameLen-len(ext)] + ext
	}
	return safe
}

// allowedMIMEByExt maps extension to allowed MIME types (first is primary).
var allowedMIMEByExt = map[string][]string{
	".pdf":  {"application/pdf"},
	".png":  {"image/png"},
	".jpg":  {"image/jpeg"},
	".jpeg": {"image/jpeg"},
	".doc":  {"application/msword"},
	".docx": {"application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
	".ppt":  {"application/vnd.ms-powerpoint"},
	".pptx": {"application/vnd.openxmlformats-officedocument.presentationml.presentation"},
}

// magicBytes for quick content check (prefix only)
var pdfMagic = []byte("%PDF-")
var pngMagic = []byte("\x89PNG\r\n\x1a\n")
var jpegMagic = []byte("\xff\xd8\xff")

func contentTypeMatchesExtension(data []byte, ext string) bool {
	ext = strings.ToLower(ext)
	mimes, ok := allowedMIMEByExt[ext]
	if !ok {
		return false
	}
	switch ext {
	case ".pdf":
		return len(data) >= 5 && bytes.Equal(data[:5], pdfMagic)
	case ".png":
		return len(data) >= 8 && bytes.Equal(data[:8], pngMagic)
	case ".jpg", ".jpeg":
		return len(data) >= 3 && bytes.Equal(data[:3], jpegMagic)
	}
	// DOC/DOCX/PPT/PPTX: zip-based (PK) or OLE; allow if extension allowed (no magic check for brevity)
	if ext == ".docx" || ext == ".pptx" {
		return len(data) >= 4 && data[0] == 0x50 && data[1] == 0x4b // PK zip
	}
	return len(mimes) > 0
}

func generateUniqueCode(length int) string {
	// Use crypto/rand so file codes are unpredictable (security: file download is gated by this code).
	for retry := 0; retry < 3; retry++ {
		b := make([]byte, length)
		if _, err := rand.Read(b); err != nil {
			continue
		}
		for i := range b {
			b[i] = charset[int(b[i])%len(charset)]
		}
		return string(b)
	}
	// Fallback only if crypto/rand failed repeatedly; use time-derived indices into charset
	n := uint64(time.Now().UnixNano())
	out := make([]byte, length)
	for i := range out {
		out[i] = charset[int((n>>(i*10))%uint64(len(charset)))]
	}
	return string(out)
}


// normalizeQueuePositions ensures queue positions are sequential (1, 2, 3...) based on FIFO (created_at).
// Only active queue files (uploaded, printing) are numbered; cancelled are excluded so positions have no gaps.
func normalizeQueuePositions(shopID int) {
	// Get all active queue files (exclude downloaded, withdrawn, cancelled) ordered by created_at (FIFO)
	rows, err := database.DB.Query(context.Background(),
		`SELECT id FROM files 
		 WHERE shop_id = $1 AND status != 'downloaded' AND status != 'withdrawn' AND status != 'cancelled' AND print_type = 'queue'
		 ORDER BY created_at ASC`, shopID)
	if err != nil {
		return
	}
	defer rows.Close()

	var fileIDs []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			continue
		}
		fileIDs = append(fileIDs, id)
	}

	// Update positions sequentially starting from 1
	for i, id := range fileIDs {
		newPos := i + 1
		database.DB.Exec(context.Background(),
			"UPDATE files SET queue_position = $1 WHERE id = $2", newPos, id)
	}
}

// processSingleFile processes a single file upload and returns file info
func processSingleFile(
	handler *multipart.FileHeader,
	userID int,
	printType string,
	copies int,
	printMode string,
	colorMode string,
	paperSize string,
	commentPtr *string,
	paymentOrderID int,
	paymentStatus string,
	paymentAmount float64,
	paymentShopkeeperID *int,
	shopID *int,
	queuePosition *int,
	ctx context.Context,
) (map[string]interface{}, error) {
	// Validate file size
	const maxFileSize = 20 << 20 // 20MB per file
	if handler.Size > maxFileSize {
		return nil, fmt.Errorf("file '%s' exceeds maximum limit of 20MB per file", handler.Filename)
	}

	// Validate file extension
	ext := strings.ToLower(filepath.Ext(handler.Filename))
	allowedExtensions := map[string]bool{
		".pdf": true, ".png": true, ".jpg": true, ".jpeg": true,
		".doc": true, ".docx": true, ".ppt": true, ".pptx": true,
	}
	if !allowedExtensions[ext] {
		return nil, fmt.Errorf("file type not supported: PDF, images (PNG/JPG/JPEG), Word (DOC/DOCX), PowerPoint (PPT/PPTX)")
	}

	// Open and read file
	file, err := handler.Open()
	if err != nil {
		return nil, fmt.Errorf("error opening file")
	}
	defer file.Close()

	fileBytes, err := io.ReadAll(file)
	if err != nil {
		return nil, fmt.Errorf("error reading file")
	}

	// MIME / content validation: magic bytes must match extension
	if !contentTypeMatchesExtension(fileBytes, ext) {
		return nil, fmt.Errorf("file content does not match extension")
	}

	// Image validation: decode to reject corrupted PNG/JPEG
	if err := utils.ValidateImageBytes(fileBytes, ext); err != nil {
		return nil, err
	}

	// Count pages: PDF = count; PPTX = slides; DOCX = estimated pages; images, DOC, PPT = 1
	var numPages int
	switch ext {
	case ".pdf":
		numPages, err = utils.CountPDFPagesFromReader(bytes.NewReader(fileBytes))
		if err != nil {
			if errors.Is(err, utils.ErrPageCountNotAvailable) {
				return nil, fmt.Errorf(utils.PageCountNotAvailableMessage)
			}
			return nil, fmt.Errorf("PDF appears corrupted or invalid; please use a valid PDF file")
		}
	case ".pptx":
		numPages, err = utils.CountPPTXSlides(bytes.NewReader(fileBytes))
		if err != nil {
			if errors.Is(err, utils.ErrPageCountNotAvailable) {
				return nil, fmt.Errorf(utils.PageCountNotAvailableMessage)
			}
			return nil, fmt.Errorf("PowerPoint file appears corrupted or invalid")
		}
		if numPages < 1 {
			numPages = 1
		}
	case ".docx":
		numPages, err = utils.CountDOCXPages(bytes.NewReader(fileBytes))
		if err != nil {
			if errors.Is(err, utils.ErrPageCountNotAvailable) {
				return nil, fmt.Errorf(utils.PageCountNotAvailableMessage)
			}
			return nil, fmt.Errorf("Word file appears corrupted or invalid")
		}
		if numPages < 1 {
			numPages = 1
		}
	case ".ppt":
		numPages, err = utils.CountPPTSlides(bytes.NewReader(fileBytes))
		if err != nil {
			if errors.Is(err, utils.ErrPageCountNotAvailable) {
				return nil, fmt.Errorf(utils.PageCountNotAvailableMessage)
			}
			return nil, fmt.Errorf("PowerPoint file appears corrupted or invalid")
		}
		if numPages < 1 {
			numPages = 1
		}
	case ".doc":
		numPages, err = utils.CountDOCPages(bytes.NewReader(fileBytes))
		if err != nil {
			if errors.Is(err, utils.ErrPageCountNotAvailable) {
				return nil, fmt.Errorf(utils.PageCountNotAvailableMessage)
			}
			return nil, fmt.Errorf("Word file appears corrupted or invalid")
		}
		if numPages < 1 {
			numPages = 1
		}
	default:
		numPages = 1 // images
	}

	// Sanitize filename (no path traversal, safe chars only)
	safeName := sanitizeFilename(handler.Filename)
	filename := fmt.Sprintf("%d-%s", time.Now().Unix(), safeName)
	filePath, err := fileStorage.Upload(ctx, bytes.NewReader(fileBytes), filename)
	if err != nil {
		return nil, fmt.Errorf("error saving file: %v", err)
	}

	// Calculate cost for this file (platform or shop rates; double-sided factor)
	totalCost := ComputeOrderCost(numPages, copies, colorMode, printMode, shopID)

	// Generate unique code
	uniqueCode := generateUniqueCode(6)

	// Insert into database
	var fileID int
	testModeInsert := isTestMode()

	if testModeInsert && paymentOrderID == 0 {
		var paymentOrderIDInterface interface{} = nil
		err = database.DB.QueryRow(context.Background(),
			`INSERT INTO files (user_id, file_path, unique_code, print_type, copies, print_mode, 
			 color_mode, paper_size, num_pages, total_cost, shop_id, queue_position, comment, 
			 payment_order_id, payment_status) 
			 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15) RETURNING id`,
			userID, filePath, uniqueCode, printType, copies, printMode,
			colorMode, paperSize, numPages, totalCost, shopID, queuePosition, commentPtr,
			paymentOrderIDInterface, "paid").Scan(&fileID)
	} else {
		err = database.DB.QueryRow(context.Background(),
			`INSERT INTO files (user_id, file_path, unique_code, print_type, copies, print_mode, 
			 color_mode, paper_size, num_pages, total_cost, shop_id, queue_position, comment, 
			 payment_order_id, payment_status) 
			 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15) RETURNING id`,
			userID, filePath, uniqueCode, printType, copies, printMode,
			colorMode, paperSize, numPages, totalCost, shopID, queuePosition, commentPtr,
			paymentOrderID, "paid").Scan(&fileID)
	}

	if err != nil {
		// Clean up uploaded file on error
		fileStorage.Delete(ctx, filePath)
		return nil, fmt.Errorf("database error: %v", err)
	}

	result := map[string]interface{}{
		"id":         fileID,
		"filename":   handler.Filename,
		"file_path":  filePath,
		"num_pages":  numPages,
		"total_cost": totalCost,
		"unique_code": uniqueCode,
	}

	if printType == "private" {
		result["code"] = uniqueCode
	}
	if queuePosition != nil {
		result["queue_position"] = *queuePosition
	}

	return result, nil
}

func UploadFile(w http.ResponseWriter, r *http.Request) {
	// Limit total form size to 100MB (for batch uploads)
	const maxGroupSize = 100 << 20 // 100MB total
	const maxFileSize = 20 << 20   // 20MB per file
	r.ParseMultipartForm(maxGroupSize)

	// Get user ID from context
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	userID := claims.UserID

	// Parse print settings from form data
	printType := r.FormValue("print_type")
	if printType == "" {
		printType = "private"
	}

	copies, _ := strconv.Atoi(r.FormValue("copies"))
	if copies < 1 {
		copies = 1
	}

	printMode := r.FormValue("print_mode")
	if printMode == "" {
		printMode = "single"
	}

	colorMode := r.FormValue("color_mode")
	if colorMode == "" {
		colorMode = "bw"
	}

	paperSize := r.FormValue("paper_size")
	if paperSize == "" {
		paperSize = "A4"
	}

	// Get comment (optional)
	comment := r.FormValue("comment")
	var commentPtr *string
	if comment != "" {
		commentPtr = &comment
	}

	// Get files - support both single and multiple
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
		if handler.Size > maxFileSize {
			http.Error(w, fmt.Sprintf("File '%s' exceeds maximum limit of 20MB per file", handler.Filename), http.StatusBadRequest)
			return
		}

		ext := filepath.Ext(handler.Filename)
		if !allowedExtensions[ext] {
			http.Error(w, fmt.Sprintf("File '%s': %s", handler.Filename, supportedMsg), http.StatusBadRequest)
			return
		}

		totalSize += handler.Size
	}

	if totalSize > maxGroupSize {
		http.Error(w, fmt.Sprintf("Total file size (%.2fMB) exceeds maximum limit of 100MB", float64(totalSize)/(1024*1024)), http.StatusBadRequest)
		return
	}

	ctx := r.Context()

	// Calculate total cost for all files first (for payment verification)
	totalPages := 0
	for _, handler := range fileHeaders {
		file, err := handler.Open()
		if err != nil {
			continue
		}
		fileBytes, err := io.ReadAll(file)
		file.Close()
		if err != nil {
			continue
		}

		ext := filepath.Ext(handler.Filename)
		if err := utils.ValidateImageBytes(fileBytes, ext); err != nil {
			http.Error(w, fmt.Sprintf("File '%s': %v", handler.Filename, err), http.StatusBadRequest)
			return
		}
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
			if numPages == 0 {
				numPages = 1
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
	}

	// Check if we're in test mode (allow skipping payment only in dev/test)
	testMode := isTestMode()

	// PAYMENT VERIFICATION: Resolve payment order and shopID first so we can compute cost with correct shop pricing
	paymentOrderIDStr := r.FormValue("payment_order_id")
	var paymentOrderID int
	var paymentStatus string
	var paymentAmount float64
	var paymentShopkeeperID *int

	if paymentOrderIDStr == "" {
		if !testMode {
			http.Error(w, "Payment order ID is required. Please complete payment first.", http.StatusPaymentRequired)
			return
		}
		paymentOrderID = 0
		paymentStatus = "paid"
		paymentShopkeeperID = nil
		if printType == "queue" {
			if shopIDStr := r.FormValue("shop_id"); shopIDStr != "" {
				if sid, err := strconv.Atoi(shopIDStr); err == nil && sid > 0 && sid <= 999999999 {
					paymentShopkeeperID = &sid
				}
			}
		}
	} else {
		var err error
		paymentOrderID, err = strconv.Atoi(paymentOrderIDStr)
		if err != nil {
			if !testMode {
				http.Error(w, "Invalid payment order ID", http.StatusBadRequest)
				return
			}
			paymentOrderID = 0
			paymentStatus = "paid"
			paymentShopkeeperID = nil
		} else {
			err = database.DB.QueryRow(context.Background(),
				`SELECT status, amount, shopkeeper_id 
				 FROM payment_orders 
				 WHERE id = $1 AND user_id = $2`,
				paymentOrderID, userID).Scan(&paymentStatus, &paymentAmount, &paymentShopkeeperID)
			if err != nil {
				if !testMode {
					http.Error(w, "Payment order not found", http.StatusNotFound)
					return
				}
				paymentStatus = "paid"
				paymentAmount = 0
				paymentShopkeeperID = nil
			}
		}
	}

	// Compute expected total cost using same formula as calculate-cost (platform or shop rates; double-sided factor)
	shopIDForCost := paymentShopkeeperID
	totalCost := ComputeOrderCost(totalPages, copies, colorMode, printMode, shopIDForCost)

	if paymentOrderIDStr == "" && testMode {
		paymentAmount = totalCost
	}

	// Verify payment order (skip in test mode if using dummy ID)
	if paymentOrderID != 0 {
		if !testMode && paymentStatus != "paid" {
			http.Error(w, fmt.Sprintf("Payment not completed. Status: %s", paymentStatus), http.StatusPaymentRequired)
			return
		}

		if !testMode && math.Abs(paymentAmount-totalCost) > 0.01 {
			http.Error(w, fmt.Sprintf("Payment amount mismatch. Expected: %.2f, Paid: %.2f", totalCost, paymentAmount), http.StatusBadRequest)
			return
		}

		if !testMode {
			var paymentPrintType string
			var paymentCopies int
			var paymentPrintMode, paymentColorMode, paymentPaperSize string
			err := database.DB.QueryRow(context.Background(),
				`SELECT print_type, copies, print_mode, color_mode, paper_size 
				 FROM payment_orders WHERE id = $1`,
				paymentOrderID).Scan(&paymentPrintType, &paymentCopies, &paymentPrintMode, &paymentColorMode, &paymentPaperSize)

			if err == nil {
				if paymentPrintType != printType || paymentCopies != copies ||
					paymentPrintMode != printMode || paymentColorMode != colorMode || paymentPaperSize != paperSize {
					http.Error(w, "Print configuration does not match payment order", http.StatusBadRequest)
					return
				}
			}
		}
	}

	// Handle queue print - calculate queue position once for all files
	var shopID *int
	var queuePosition *int

	if printType == "queue" {
		if paymentShopkeeperID != nil {
			shopID = paymentShopkeeperID
			var activeCount int
			err := database.DB.QueryRow(context.Background(),
				`SELECT COUNT(DISTINCT payment_order_id) FROM files 
				 WHERE shop_id = $1 AND status != 'downloaded' AND status != 'withdrawn' AND print_type = 'queue'`,
				*shopID).Scan(&activeCount)
			if err == nil {
				newPos := activeCount + 1
				queuePosition = &newPos
			}
		} else {
			shopIDStr := r.FormValue("shop_id")
			if shopIDStr != "" {
				sid, err := strconv.Atoi(shopIDStr)
				if err == nil {
					var shopExists bool
					err = database.DB.QueryRow(context.Background(),
						"SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND role = 'shopkeeper')", sid).Scan(&shopExists)
					if err != nil || !shopExists {
						http.Error(w, "Shop not found", http.StatusNotFound)
						return
					}
					shopID = &sid
					var activeCount int
					err = database.DB.QueryRow(context.Background(),
						`SELECT COUNT(DISTINCT payment_order_id) FROM files 
						 WHERE shop_id = $1 AND status != 'downloaded' AND status != 'withdrawn' AND print_type = 'queue'`,
						sid).Scan(&activeCount)
					if err == nil {
						newPos := activeCount + 1
						queuePosition = &newPos
					}
				}
			}
		}
	}

	// Process all files
	var uploadedFiles []map[string]interface{}
	var totalUploadedPages int
	var totalUploadedCost float64
	var firstUniqueCode string

	for i, handler := range fileHeaders {
		fileInfo, err := processSingleFile(
			handler, userID, printType, copies, printMode, colorMode, paperSize,
			commentPtr, paymentOrderID, paymentStatus, paymentAmount, paymentShopkeeperID,
			shopID, queuePosition, ctx,
		)

		if err != nil {
			// Clean up already uploaded files on error
			for _, uploaded := range uploadedFiles {
				if filePath, ok := uploaded["file_path"].(string); ok {
					fileStorage.Delete(ctx, filePath)
				}
			}
			msg := fmt.Sprintf("Error processing file '%s': %v", handler.Filename, err)
			status := http.StatusInternalServerError
			if strings.Contains(err.Error(), "corrupted") || strings.Contains(err.Error(), "does not match") ||
				strings.Contains(err.Error(), "exceeds maximum") || strings.Contains(err.Error(), "not supported") {
				status = http.StatusBadRequest
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(status)
			json.NewEncoder(w).Encode(map[string]string{"error": msg})
			return
		}

		if i == 0 && printType == "private" {
			firstUniqueCode = fileInfo["unique_code"].(string)
		}

		totalUploadedPages += fileInfo["num_pages"].(int)
		totalUploadedCost += fileInfo["total_cost"].(float64)
		uploadedFiles = append(uploadedFiles, fileInfo)
	}

	// Normalize queue positions if needed
	if printType == "queue" && shopID != nil {
		normalizeQueuePositions(*shopID)
		var shopName string
		_ = database.DB.QueryRow(context.Background(), "SELECT COALESCE(NULLIF(TRIM(shop_name), ''), 'Shop') FROM users WHERE id = $1", *shopID).Scan(&shopName)
		msg := "Your print has been added to the queue."
		if shopName != "" {
			msg = "Your print has been added to the queue at " + shopName + "."
		}
		if queuePosition != nil {
			msg += " Position #" + strconv.Itoa(*queuePosition) + "."
		}
		notifications.SendToUser(userID, "Order accepted", msg, map[string]string{"type": "order_accepted"})
		// Notify connected shopkeeper app(s) in real time (Windows SSE)
		shopkeeperstream.NotifyShopNewQueueJob(*shopID, len(uploadedFiles))
	}

	// Prepare response
	response := map[string]interface{}{
		"file_count":    len(uploadedFiles),
		"total_pages":   totalUploadedPages,
		"total_cost":    totalUploadedCost,
		"files":         uploadedFiles,
		"queue_position": queuePosition,
	}

	if printType == "private" && firstUniqueCode != "" {
		response["code"] = firstUniqueCode
	}

	// For backward compatibility, also include single file response format
	if len(uploadedFiles) == 1 {
		response["file_id"] = uploadedFiles[0]["id"]
		response["num_pages"] = uploadedFiles[0]["num_pages"]
		if code, ok := uploadedFiles[0]["code"].(string); ok {
			response["code"] = code
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func DownloadFile(w http.ResponseWriter, r *http.Request) {
	code := chi.URLParam(r, "code")

	var filePath, status string
	err := database.DB.QueryRow(context.Background(),
		"SELECT file_path, status FROM files WHERE unique_code = $1", code).Scan(&filePath, &status)

	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}

	// Check if file has already been downloaded
	if status == "downloaded" {
		http.Error(w, "File has already been downloaded and is no longer available", http.StatusGone)
		return
	}

	// Get file from storage
	ctx := r.Context()
	fileReader, err := fileStorage.GetFile(ctx, filePath)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}
	defer fileReader.Close()

	// Determine content type based on file extension
	ext := filepath.Ext(filePath)
	contentType := "application/octet-stream"
	switch ext {
	case ".pdf":
		contentType = "application/pdf"
	case ".png":
		contentType = "image/png"
	case ".jpg", ".jpeg":
		contentType = "image/jpeg"
	case ".doc":
		contentType = "application/msword"
	case ".docx":
		contentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
	case ".ppt":
		contentType = "application/vnd.ms-powerpoint"
	case ".pptx":
		contentType = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
	}

	w.Header().Set("Content-Type", contentType)
	io.Copy(w, fileReader)

	// NOTE: File is no longer auto-deleted here.
	// Shopkeeper must confirm print completion via /file/:code/confirm endpoint
}

func CheckFileStatus(w http.ResponseWriter, r *http.Request) {
	code := chi.URLParam(r, "code")

	var paymentOrderID *int
	var filePath string
	var copies int
	var printMode, colorMode, paperSize string
	err := database.DB.QueryRow(context.Background(),
		`SELECT payment_order_id, file_path, copies, print_mode, color_mode, paper_size FROM files WHERE unique_code = $1`,
		code).Scan(&paymentOrderID, &filePath, &copies, &printMode, &colorMode, &paperSize)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}

	// Order-level status for private print: any file in the order determines status; num_pages = sum across order
	var status string
	var totalPages int
	if paymentOrderID != nil {
		var anyDownloaded, anyPrinting int
		_ = database.DB.QueryRow(context.Background(),
			`SELECT COALESCE(MAX(CASE WHEN status = 'downloaded' THEN 1 ELSE 0 END), 0),
			        COALESCE(MAX(CASE WHEN status = 'printing' THEN 1 ELSE 0 END), 0),
			        COALESCE(SUM(num_pages), 0)
			 FROM files WHERE payment_order_id = $1`, *paymentOrderID).Scan(&anyDownloaded, &anyPrinting, &totalPages)
		if anyDownloaded == 1 {
			status = "downloaded"
		} else if anyPrinting == 1 {
			status = "printing"
		} else {
			status = "uploaded"
		}
	} else {
		var s string
		var np int
		_ = database.DB.QueryRow(context.Background(), `SELECT status, num_pages FROM files WHERE unique_code = $1`, code).Scan(&s, &np)
		status = s
		totalPages = np
	}

	fileExtension := filepath.Ext(filePath)
	if fileExtension == "" {
		fileExtension = ".pdf"
	}

	response := map[string]interface{}{
		"status":         status,
		"copies":         copies,
		"print_mode":     printMode,
		"color_mode":     colorMode,
		"paper_size":     paperSize,
		"file_extension": fileExtension,
		"num_pages":      totalPages,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// getShopPricing returns price_per_page_bw, price_per_page_color, double_sided_factor for a shopkeeper.
// Returns (nil, nil, nil) if shopID is not a valid shopkeeper (so caller uses platform defaults).
func getShopPricing(shopID int) (rateBW, rateColor, factorDouble *float64) {
	var bw, color, factor *float64
	err := database.DB.QueryRow(context.Background(),
		`SELECT price_per_page_bw, price_per_page_color, double_sided_factor 
		 FROM users WHERE id = $1 AND role = 'shopkeeper'`,
		shopID).Scan(&bw, &color, &factor)
	if err != nil {
		return nil, nil, nil
	}
	return bw, color, factor
}

// ComputeOrderCost returns total cost for given pages/copies/color/printMode, using shop pricing when shopID is set and valid.
// Security: shopID is only used if it refers to a real shopkeeper; otherwise platform defaults are used.
func ComputeOrderCost(pages, copies int, colorMode, printMode string, shopID *int) float64 {
	var rateBW, rateColor, factorDouble *float64
	if shopID != nil && *shopID > 0 {
		rateBW, rateColor, factorDouble = getShopPricing(*shopID)
	}
	return utils.CalculateCostFromParams(utils.CostParams{
		Pages:             pages,
		Copies:            copies,
		ColorMode:         colorMode,
		PrintMode:         printMode,
		RateBW:            rateBW,
		RateColor:         rateColor,
		DoubleSidedFactor: factorDouble,
	})
}

func GetNearestShops(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Get user location (optional - customers may not have location)
	var userLat, userLong *float64
	err := database.DB.QueryRow(context.Background(),
		"SELECT lat, long FROM users WHERE id = $1", claims.UserID).Scan(&userLat, &userLong)

	// If user doesn't have location, that's okay - we'll show shops without distance calculation
	hasUserLocation := err == nil && userLat != nil && userLong != nil

	rows, err := database.DB.Query(context.Background(),
		`SELECT id, COALESCE(NULLIF(TRIM(shop_name), ''), 'Shop') AS shop_name, lat, long, address, is_open, price_per_page_bw, price_per_page_color, double_sided_factor FROM users WHERE role = 'shopkeeper'`)
	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	// Debug: Count total shopkeepers
	var totalShopkeepers int
	database.DB.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM users WHERE role = 'shopkeeper'").Scan(&totalShopkeepers)
	fmt.Printf("DEBUG: Total shopkeepers in database: %d\n", totalShopkeepers)

	platformBW := utils.GetCostPerPageBW()
	platformColor := utils.GetCostPerPageColor()

	type Shop struct {
		ID                      int      `json:"id"`
		ShopName                string   `json:"shop_name"`
		Distance                *float64 `json:"distance,omitempty"`
		Address                 *string  `json:"address,omitempty"`
		Lat                     float64  `json:"lat"`
		Long                    float64  `json:"long"`
		IsOpen                  bool     `json:"is_open"`
		PricePerPageBW          *float64 `json:"price_per_page_bw,omitempty"`
		PricePerPageColor       *float64 `json:"price_per_page_color,omitempty"`
		EffectivePricePerPageBW float64  `json:"effective_price_per_page_bw"`
		EffectivePricePerPageColor float64 `json:"effective_price_per_page_color"`
		DoubleSidedFactor       *float64 `json:"double_sided_factor,omitempty"`
	}

	shops := []Shop{}
	for rows.Next() {
		var id int
		var shopName string
		var lat, long *float64
		var address *string
		var isOpen bool
		var priceBW, priceColor, factorDouble *float64
		if err := rows.Scan(&id, &shopName, &lat, &long, &address, &isOpen, &priceBW, &priceColor, &factorDouble); err != nil {
			fmt.Printf("Error scanning shop row: %v\n", err)
			continue
		}

		// Skip shops without valid location
		if lat == nil || long == nil {
			fmt.Printf("Skipping shop %d (%s) - missing location (lat: %v, long: %v)\n", id, shopName, lat, long)
			continue
		}

		// Calculate distance only if user has location
		var distance *float64
		if hasUserLocation {
			dist := haversine(*userLat, *userLong, *lat, *long)
			distance = &dist
		}

		effBW := platformBW
		if priceBW != nil {
			effBW = *priceBW
		}
		effColor := platformColor
		if priceColor != nil {
			effColor = *priceColor
		}
		shops = append(shops, Shop{
			ID:                        id,
			ShopName:                  shopName,
			Distance:                  distance,
			Address:                   address,
			Lat:                       *lat,
			Long:                      *long,
			IsOpen:                    isOpen,
			PricePerPageBW:            priceBW,
			PricePerPageColor:         priceColor,
			EffectivePricePerPageBW:   effBW,
			EffectivePricePerPageColor: effColor,
			DoubleSidedFactor:         factorDouble,
		})
	}

	fmt.Printf("DEBUG: Returning %d shops (out of %d total shopkeepers)\n", len(shops), totalShopkeepers)

	// Sort shops by distance (if available), otherwise keep original order
	if hasUserLocation {
		sort.Slice(shops, func(i, j int) bool {
			if shops[i].Distance == nil {
				return false
			}
			if shops[j].Distance == nil {
				return true
			}
			return *shops[i].Distance < *shops[j].Distance
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(shops)
}

// GetShopByID returns a single shop by ID or by 6-digit shop_code for customers (e.g. after scanning QR or entering code).
// Requires auth. id param: numeric user id (e.g. 42) or 6-digit shop code (e.g. 123456). Returns 404 if not found.
func GetShopByID(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	idStr := chi.URLParam(r, "id")
	if idStr == "" {
		http.Error(w, "Invalid shop id", http.StatusBadRequest)
		return
	}
	// If 6 digits, treat as shop_code lookup; otherwise as numeric id
	var shopID int
	if len(idStr) == 6 && idStr[0] >= '1' && idStr[0] <= '9' {
		for _, c := range idStr {
			if c < '0' || c > '9' {
				http.Error(w, "Invalid shop code", http.StatusBadRequest)
				return
			}
		}
		code, _ := strconv.Atoi(idStr)
		err := database.DB.QueryRow(context.Background(),
			"SELECT id FROM users WHERE shop_code = $1 AND role = 'shopkeeper'", code).Scan(&shopID)
		if err != nil {
			http.Error(w, "Shop not found", http.StatusNotFound)
			return
		}
	} else {
		var err error
		shopID, err = strconv.Atoi(idStr)
		if err != nil || shopID <= 0 || shopID > 999999999 {
			http.Error(w, "Invalid shop id", http.StatusBadRequest)
			return
		}
	}
	var shopName string
	var lat, long *float64
	var address *string
	var isOpen bool
	var shopCode *int
	var priceBW, priceColor, factorDouble *float64
	err := database.DB.QueryRow(context.Background(),
		`SELECT COALESCE(NULLIF(TRIM(shop_name), ''), 'Shop'), lat, long, address, is_open, shop_code, price_per_page_bw, price_per_page_color, double_sided_factor FROM users WHERE id = $1 AND role = 'shopkeeper'`,
		shopID).Scan(&shopName, &lat, &long, &address, &isOpen, &shopCode, &priceBW, &priceColor, &factorDouble)
	if err != nil || lat == nil || long == nil {
		http.Error(w, "Shop not found", http.StatusNotFound)
		return
	}
	// Optional: distance for current user
	var userLat, userLong *float64
	_ = database.DB.QueryRow(context.Background(),
		"SELECT lat, long FROM users WHERE id = $1", claims.UserID).Scan(&userLat, &userLong)
	var distance *float64
	if userLat != nil && userLong != nil {
		d := haversine(*userLat, *userLong, *lat, *long)
		distance = &d
	}
	out := map[string]interface{}{
		"id":        shopID,
		"shop_name": shopName,
		"lat":      *lat,
		"long":     *long,
		"is_open":  isOpen,
	}
	if shopCode != nil {
		out["shop_code"] = *shopCode
	}
	if address != nil {
		out["address"] = *address
	}
	if distance != nil {
		out["distance"] = *distance
	}
	if priceBW != nil {
		out["price_per_page_bw"] = *priceBW
	}
	if priceColor != nil {
		out["price_per_page_color"] = *priceColor
	}
	platformBW := utils.GetCostPerPageBW()
	platformColor := utils.GetCostPerPageColor()
	effBW := platformBW
	if priceBW != nil {
		effBW = *priceBW
	}
	effColor := platformColor
	if priceColor != nil {
		effColor = *priceColor
	}
	out["effective_price_per_page_bw"] = effBW
	out["effective_price_per_page_color"] = effColor
	if factorDouble != nil {
		out["double_sided_factor"] = *factorDouble
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(out)
}

// ShopRedirectPage serves a public HTML page for /s/{id} (shop QR link).
// When scanned outside the customer app: tries to open the app, then redirects to Play Store or website.
// Security: id validated as positive int; shop existence checked; no user input reflected in HTML; rate-limited by caller.
func ShopRedirectPage(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	if idStr == "" {
		http.Error(w, "Invalid link", http.StatusBadRequest)
		return
	}
	shopID, err := strconv.Atoi(idStr)
	if err != nil || shopID <= 0 || shopID > 999999999 {
		http.Error(w, "Invalid link", http.StatusBadRequest)
		return
	}
	var exists bool
	err = database.DB.QueryRow(context.Background(),
		"SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND role = 'shopkeeper')", shopID).Scan(&exists)
	if err != nil || !exists {
		http.Error(w, "Shop not found", http.StatusNotFound)
		return
	}
	websiteURL := os.Getenv("SHOP_REDIRECT_WEBSITE_URL")
	if websiteURL == "" {
		websiteURL = "https://qprint.co.in"
	}
	websiteURL = strings.TrimSuffix(websiteURL, "/")
	androidURL := os.Getenv("ANDROID_APP_URL")
	if androidURL == "" {
		androidURL = "https://play.google.com/store/apps/details?id=com.qprintsolutions.qprint"
	}
	iosURL := os.Getenv("IOS_APP_URL")
	if iosURL == "" {
		iosURL = websiteURL
	}
	// Escape for HTML attributes to prevent XSS
	websiteURL = html.EscapeString(websiteURL)
	androidURL = html.EscapeString(androidURL)
	iosURL = html.EscapeString(iosURL)
	// Deep link: app opens with this scheme (customer app parses and does not open in browser)
	appScheme := "qprint://shop/" + strconv.Itoa(shopID)
	// Intent URL for Android (optional; some browsers open app from intent)
	intentURL := "intent://shop/" + strconv.Itoa(shopID) + "#Intent;scheme=qprint;package=com.qprintsolutions.qprint;end"
	// Escape for use inside JavaScript string (backslash and quote)
	jsEscape := func(s string) string {
		return strings.ReplaceAll(strings.ReplaceAll(s, `\`, `\\`), `"`, `\"`)
	}
	intentURLJS := jsEscape(intentURL)
	appSchemeJS := jsEscape(appScheme)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(http.StatusOK)
	// Try app first; after delay redirect to store/website. No unescaped user input in script.
	htmlBody := `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Open in Qprint – Print at this shop</title>
  <meta http-equiv="refresh" content="3;url=` + androidURL + `">
  <style>
    body { font-family: system-ui, sans-serif; max-width: 480px; margin: 2rem auto; padding: 1rem; text-align: center; background: #1a1a2e; color: #eee; }
    a { color: #ec4899; }
    .btn { display: inline-block; margin: 0.5rem; padding: 12px 24px; background: #ec4899; color: #fff; text-decoration: none; border-radius: 8px; font-weight: 600; }
    .btn:hover { opacity: 0.9; }
  </style>
</head>
<body>
  <h1>Print at this shop</h1>
  <p>Opening the Qprint app…</p>
  <p>If the app doesn't open, <a href="` + androidURL + `">download Qprint on Google Play</a> or visit <a href="` + websiteURL + `">` + websiteURL + `</a>.</p>
  <p><a class="btn" href="` + androidURL + `">Get the app</a></p>
  <script>
    (function(){
      var ua = navigator.userAgent;
      var isAndroid = /Android/i.test(ua);
      var intent = "` + intentURLJS + `";
      var scheme = "` + appSchemeJS + `";
      try {
        if (isAndroid && intent) window.location.href = intent;
        else if (scheme) window.location.href = scheme;
      } catch (e) {}
      setTimeout(function(){ window.location.href = "` + androidURL + `"; }, 2500);
    })();
  </script>
</body>
</html>`
	w.Write([]byte(htmlBody))
}

func GetShopQueue(w http.ResponseWriter, r *http.Request) {
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

	// Normalize queue positions to ensure sequential numbering (1, 2, 3...)
	normalizeQueuePositions(claims.UserID)

	// Group files by order only (one queue entry per order). Do not group by copies/print_mode/etc
	// or the same order can appear multiple times and confirming one would remove all duplicate rows.
	// MIN(f.id) gives a file id for cancel/print-started (any file in the order).
	rows, err := database.DB.Query(context.Background(),
		`SELECT 
			COALESCE(f.payment_order_id, f.id) as order_group_id,
			MIN(f.id) as first_file_id,
			MIN(f.queue_position) as queue_position,
			COALESCE(NULLIF(TRIM(u.full_name), ''), NULLIF(TRIM(u.email), ''), u.phone, 'Customer') as customer_name,
			COUNT(f.id) as file_count,
			SUM(f.num_pages) as total_pages,
			SUM(f.total_cost) as total_cost,
			MIN(f.created_at) as created_at,
			MAX(f.comment) as comment,
			MAX(f.copies) as copies,
			MAX(f.print_mode) as print_mode,
			MAX(f.color_mode) as color_mode,
			MAX(f.paper_size) as paper_size,
			MAX(f.status::text) as status
		 FROM files f
		 JOIN users u ON f.user_id = u.id
		 WHERE f.shop_id = $1 AND f.status != 'downloaded' AND f.status != 'withdrawn' AND f.status != 'cancelled' AND f.print_type = 'queue'
		 GROUP BY COALESCE(f.payment_order_id, f.id), COALESCE(NULLIF(TRIM(u.full_name), ''), NULLIF(TRIM(u.email), ''), u.phone, 'Customer')
		 ORDER BY MIN(f.queue_position) ASC`, claims.UserID)

	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type OrderGroup struct {
		OrderGroupID  interface{} `json:"order_group_id"`
		FirstFileID   int         `json:"first_file_id"`
		QueuePosition *int        `json:"queue_position"`
		CustomerName  string      `json:"customer_name"`
		FileCount     int         `json:"file_count"`
		TotalPages    int         `json:"total_pages"`
		TotalCost     float64     `json:"total_cost"`
		CreatedAt     time.Time   `json:"created_at"`
		Comment       *string     `json:"comment,omitempty"`
		Copies        int         `json:"copies"`
		PrintMode     string      `json:"print_mode"`
		ColorMode     string      `json:"color_mode"`
		PaperSize     string      `json:"paper_size"`
		Status        string      `json:"status"` // "uploaded" or "printing" (stuck e.g. after app crash)
	}

	var queue []OrderGroup
	for rows.Next() {
		var og OrderGroup
		var queuePos *int
		var status string
		if err := rows.Scan(&og.OrderGroupID, &og.FirstFileID, &queuePos, &og.CustomerName, &og.FileCount,
			&og.TotalPages, &og.TotalCost, &og.CreatedAt, &og.Comment,
			&og.Copies, &og.PrintMode, &og.ColorMode, &og.PaperSize, &status); err != nil {
			continue
		}
		og.QueuePosition = queuePos
		og.Status = status
		queue = append(queue, og)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"queue": queue})
}

// GetOrderFiles returns all files for a payment order
func GetOrderFiles(w http.ResponseWriter, r *http.Request) {
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

	orderGroupIDStr := chi.URLParam(r, "orderGroupId")
	if orderGroupIDStr == "" {
		http.Error(w, "Order group ID required", http.StatusBadRequest)
		return
	}

	// Try to parse as payment_order_id first, then as file_id
	var orderGroupID interface{}
	if paymentOrderID, err := strconv.Atoi(orderGroupIDStr); err == nil {
		orderGroupID = paymentOrderID
	} else {
		orderGroupID = orderGroupIDStr
	}

	rows, err := database.DB.Query(context.Background(),
		`SELECT f.id, f.file_path, f.num_pages, f.total_cost, f.created_at, f.unique_code
		 FROM files f
		 WHERE (f.payment_order_id = $1 OR f.id = $1) AND f.shop_id = $2 
		   AND f.status != 'downloaded' AND f.status != 'withdrawn' AND f.status != 'cancelled' AND f.print_type = 'queue'
		 ORDER BY f.id ASC`,
		orderGroupID, claims.UserID)

	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type FileInfo struct {
		ID         int       `json:"id"`
		Filename   string    `json:"filename"`
		NumPages   int       `json:"num_pages"`
		TotalCost  float64   `json:"total_cost"`
		CreatedAt  time.Time `json:"created_at"`
		UniqueCode string    `json:"unique_code,omitempty"`
	}

	var files []FileInfo
	for rows.Next() {
		var fi FileInfo
		var filePath string
		var uniqueCode *string
		if err := rows.Scan(&fi.ID, &filePath, &fi.NumPages, &fi.TotalCost, &fi.CreatedAt, &uniqueCode); err != nil {
			continue
		}
		fi.Filename = filepath.Base(filePath)
		if uniqueCode != nil {
			fi.UniqueCode = *uniqueCode
		}
		files = append(files, fi)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"files": files})
}

func DownloadQueueFile(w http.ResponseWriter, r *http.Request) {
	fileIDStr := chi.URLParam(r, "fileId")
	fileID, err := strconv.Atoi(fileIDStr)
	if err != nil {
		http.Error(w, "Invalid file ID", http.StatusBadRequest)
		return
	}

	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Get file info and verify it belongs to this shop
	var filePath string
	var shopID int
	err = database.DB.QueryRow(context.Background(),
		"SELECT file_path, shop_id FROM files WHERE id = $1", fileID).Scan(&filePath, &shopID)

	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}

	if shopID != claims.UserID {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	// Get file from storage
	ctx := r.Context()
	fileReader, err := fileStorage.GetFile(ctx, filePath)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}
	defer fileReader.Close()

	// Determine content type based on file extension
	ext := filepath.Ext(filePath)
	contentType := "application/octet-stream"
	switch ext {
	case ".pdf":
		contentType = "application/pdf"
	case ".png":
		contentType = "image/png"
	case ".jpg", ".jpeg":
		contentType = "image/jpeg"
	case ".doc":
		contentType = "application/msword"
	case ".docx":
		contentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
	case ".ppt":
		contentType = "application/vnd.ms-powerpoint"
	case ".pptx":
		contentType = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
	}

	w.Header().Set("Content-Type", contentType)
	io.Copy(w, fileReader)

	// NOTE: File is no longer auto-deleted here.
	// Shopkeeper must confirm print completion via /queue/:fileId/confirm endpoint
}

func GetMyFiles(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	rows, err := database.DB.Query(context.Background(),
		`SELECT f.id, f.unique_code, f.print_type, f.status, f.copies, f.print_mode, 
		 f.color_mode, f.paper_size, f.num_pages, f.total_cost, f.queue_position, 
		 f.created_at, f.cancel_reason, COALESCE(NULLIF(TRIM(u.shop_name), ''), 'Shop') as shop_name, u.lat as shop_lat, u.long as shop_long
		 FROM files f
		 LEFT JOIN users u ON f.shop_id = u.id
		 WHERE f.user_id = $1
		 ORDER BY f.created_at DESC`, claims.UserID)

	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var files []map[string]interface{}
	for rows.Next() {
		var id int
		var uniqueCode, printType, status, printMode, colorMode, paperSize string
		var copies, numPages int
		var totalCost float64
		var queuePosition *int
		var createdAt time.Time
		var cancelReason *string
		var shopName *string
		var shopLat, shopLong *float64

		if err := rows.Scan(&id, &uniqueCode, &printType, &status, &copies, &printMode,
			&colorMode, &paperSize, &numPages, &totalCost, &queuePosition, &createdAt, &cancelReason, &shopName, &shopLat, &shopLong); err != nil {
			continue
		}

		fileData := map[string]interface{}{
			"id":         id,
			"code":       uniqueCode,
			"print_type": printType,
			"status":     status,
			"copies":     copies,
			"print_mode": printMode,
			"color_mode": colorMode,
			"paper_size": paperSize,
			"num_pages":  numPages,
			"total_cost": totalCost,
			"created_at": createdAt,
		}

		if queuePosition != nil {
			fileData["queue_position"] = *queuePosition
		}
		if shopName != nil {
			fileData["shop_name"] = *shopName
		}
		if shopLat != nil {
			fileData["shop_lat"] = *shopLat
		}
		if shopLong != nil {
			fileData["shop_long"] = *shopLong
		}
		if cancelReason != nil {
			fileData["cancel_reason"] = *cancelReason
		}

		files = append(files, fileData)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"files": files})
}

// GetMyOrders returns the customer's print orders grouped by batch (payment_order_id or single file).
// Each order has one queue_position for the batch, matching shopkeeper view.
func GetMyOrders(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// For private prints: group by payment_order_id only so one order = one row (no split by shop).
	// For queue: group by payment_order_id and shop_id so each shop batch is one row.
	rows, err := database.DB.Query(context.Background(),
		`SELECT 
			COALESCE(f.payment_order_id, f.id) as order_id,
			f.payment_order_id,
			f.print_type,
			MIN(f.queue_position) as queue_position,
			SUM(f.num_pages) as total_pages,
			SUM(f.total_cost) as total_cost,
			MIN(f.created_at) as created_at,
			MAX(CASE WHEN f.status = 'downloaded' THEN 1 ELSE 0 END) = 1 as any_downloaded,
			MAX(CASE WHEN f.status = 'withdrawn' THEN 1 ELSE 0 END) = 1 as any_withdrawn,
			MAX(CASE WHEN f.status = 'cancelled' THEN 1 ELSE 0 END) = 1 as any_cancelled,
			MAX(CASE WHEN f.status = 'printing' THEN 1 ELSE 0 END) = 1 as any_printing,
			MAX(CASE WHEN f.status = 'cancelled' THEN f.cancel_reason ELSE NULL END) as cancel_reason,
			MAX(COALESCE(NULLIF(TRIM(u.shop_name), ''), 'Shop')) as shop_name,
			MAX(u.lat) as shop_lat,
			MAX(u.long) as shop_long,
			f.copies,
			f.print_mode,
			f.color_mode,
			f.paper_size
		 FROM files f
		 LEFT JOIN users u ON f.shop_id = u.id
		 WHERE f.user_id = $1
		 GROUP BY COALESCE(f.payment_order_id, f.id), f.payment_order_id, f.print_type,
			(CASE WHEN f.print_type = 'queue' THEN f.shop_id END),
			f.copies, f.print_mode, f.color_mode, f.paper_size
		 ORDER BY MIN(f.created_at) DESC`, claims.UserID)

	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	// Second query: get file details for each order
	type orderRow struct {
		OrderID       interface{}
		PaymentOrderID *int
		PrintType     string
		QueuePosition *int
		TotalPages    int
		TotalCost     float64
		CreatedAt     time.Time
		AnyDownloaded bool
		AnyWithdrawn  bool
		AnyCancelled  bool
		AnyPrinting   bool
		CancelReason  *string
		ShopName      *string
		ShopLat       *float64
		ShopLong      *float64
		Copies        int
		PrintMode     string
		ColorMode     string
		PaperSize     string
	}

	var orderRows []orderRow
	for rows.Next() {
		var or orderRow
		var paymentOrderID *int
		if err := rows.Scan(&or.OrderID, &paymentOrderID, &or.PrintType, &or.QueuePosition,
			&or.TotalPages, &or.TotalCost, &or.CreatedAt, &or.AnyDownloaded, &or.AnyWithdrawn, &or.AnyCancelled, &or.AnyPrinting, &or.CancelReason,
			&or.ShopName, &or.ShopLat, &or.ShopLong, &or.Copies, &or.PrintMode, &or.ColorMode, &or.PaperSize); err != nil {
			continue
		}
		or.PaymentOrderID = paymentOrderID
		orderRows = append(orderRows, or)
	}

	// Build orders with files
	var orders []map[string]interface{}
	for _, or := range orderRows {
		orderID := or.OrderID
		if oid, ok := orderID.(int64); ok {
			orderID = int(oid)
		}

		// Derive status: cancelled > withdrawn > downloaded > printing > uploaded
		status := "uploaded"
		if or.AnyCancelled {
			status = "cancelled"
		} else if or.AnyWithdrawn {
			status = "withdrawn"
		} else if or.AnyDownloaded {
			status = "downloaded"
		} else if or.AnyPrinting {
			status = "printing"
		}

		orderData := map[string]interface{}{
			"id":           orderID,
			"print_type":   or.PrintType,
			"status":       status,
			"copies":       or.Copies,
			"print_mode":   or.PrintMode,
			"color_mode":   or.ColorMode,
			"paper_size":   or.PaperSize,
			"num_pages":    or.TotalPages,
			"total_cost":   or.TotalCost,
			"created_at":   or.CreatedAt,
			"file_count":   0, // set below
			"files":        []interface{}{}, // populated below
		}
		if or.QueuePosition != nil {
			orderData["queue_position"] = *or.QueuePosition
		}
		if or.ShopName != nil {
			orderData["shop_name"] = *or.ShopName
		}
		if or.ShopLat != nil {
			orderData["shop_lat"] = *or.ShopLat
		}
		if or.ShopLong != nil {
			orderData["shop_long"] = *or.ShopLong
		}
		if or.CancelReason != nil {
			orderData["cancel_reason"] = *or.CancelReason
		}

		// Fetch files for this order
		fileRows, err := database.DB.Query(context.Background(),
			`SELECT f.id, f.unique_code, f.file_path, f.num_pages, f.total_cost
			 FROM files f
			 WHERE f.user_id = $1 AND (f.payment_order_id = $2 OR (f.payment_order_id IS NULL AND f.id = $2))
			 ORDER BY f.id ASC`,
			claims.UserID, orderID)
		if err == nil {
			var files []map[string]interface{}
			for fileRows.Next() {
				var id int
				var uniqueCode *string
				var filePath string
				var numPages int
				var totalCost float64
				if err := fileRows.Scan(&id, &uniqueCode, &filePath, &numPages, &totalCost); err != nil {
					continue
				}
				f := map[string]interface{}{
					"id":         id,
					"num_pages":  numPages,
					"total_cost": totalCost,
					"filename":   filepath.Base(filePath),
				}
				if uniqueCode != nil {
					f["code"] = *uniqueCode
				}
				files = append(files, f)
			}
			fileRows.Close()
			orderData["files"] = files
			orderData["file_count"] = len(files)
		}

		orders = append(orders, orderData)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"orders": orders})
}

// ConfirmPrivatePrint confirms the whole private order (all files with same payment_order_id).
// One code identifies the order; all files are marked downloaded, deleted from storage, and customer is notified once.
func ConfirmPrivatePrint(w http.ResponseWriter, r *http.Request) {
	code := chi.URLParam(r, "code")

	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var role string
	if err := database.DB.QueryRow(context.Background(), "SELECT role FROM users WHERE id = $1", claims.UserID).Scan(&role); err != nil || role != "shopkeeper" {
		http.Error(w, "Only shopkeepers can confirm prints", http.StatusForbidden)
		return
	}

	var fileID int
	var status string
	var paymentOrderID *int
	var customerUserID int
	err := database.DB.QueryRow(context.Background(),
		"SELECT id, status, payment_order_id, user_id FROM files WHERE unique_code = $1", code).Scan(&fileID, &status, &paymentOrderID, &customerUserID)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}
	if status == "withdrawn" {
		http.Error(w, "This print was withdrawn by the customer and can no longer be confirmed", http.StatusGone)
		return
	}
	if status == "downloaded" {
		http.Error(w, "Print already confirmed", http.StatusGone)
		return
	}

	// Update all files in this order to downloaded + shop_id (single order = one confirm)
	var result pgconn.CommandTag
	if paymentOrderID != nil {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'downloaded', shop_id = $1 WHERE payment_order_id = $2 AND status IN ('uploaded', 'printing')",
			claims.UserID, *paymentOrderID)
	} else {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'downloaded', shop_id = $1 WHERE unique_code = $2 AND status IN ('uploaded', 'printing')",
			claims.UserID, code)
	}
	if err != nil {
		fmt.Printf("Error updating file status: %v\n", err)
		http.Error(w, "Failed to update file status", http.StatusInternalServerError)
		return
	}
	if result.RowsAffected() == 0 {
		http.Error(w, "File not found or already confirmed", http.StatusNotFound)
		return
	}

	// Payment order: assign shopkeeper and create payout (once per order)
	if paymentOrderID != nil {
		var paymentAmount float64
		var platformCommission float64
		if database.DB.QueryRow(context.Background(),
			`SELECT amount, platform_commission FROM payment_orders WHERE id = $1 AND shopkeeper_id IS NULL`, *paymentOrderID).Scan(&paymentAmount, &platformCommission) == nil {
			shopkeeperAmount := payment.CalculateShopkeeperAmount(paymentAmount, platformCommission)
			_, _ = database.DB.Exec(context.Background(),
				`UPDATE payment_orders SET shopkeeper_id = $1, shopkeeper_amount = $2 WHERE id = $3 AND shopkeeper_id IS NULL`,
				claims.UserID, shopkeeperAmount, *paymentOrderID)
			_, _ = database.DB.Exec(context.Background(),
				`INSERT INTO shopkeeper_payouts (shopkeeper_id, payment_order_id, amount, status) VALUES ($1, $2, $3, 'pending') ON CONFLICT DO NOTHING`,
				claims.UserID, *paymentOrderID, shopkeeperAmount)
		}
	}

	// Delete all files in this order from storage
	ctx := r.Context()
	var pathsToDelete []string
	if paymentOrderID != nil {
		rows, qErr := database.DB.Query(context.Background(), "SELECT file_path FROM files WHERE payment_order_id = $1", *paymentOrderID)
		if qErr == nil {
			for rows.Next() {
				var p string
				if rows.Scan(&p) == nil && p != "" {
					pathsToDelete = append(pathsToDelete, p)
				}
			}
			rows.Close()
		}
	} else {
		var p string
		if database.DB.QueryRow(context.Background(), "SELECT file_path FROM files WHERE unique_code = $1", code).Scan(&p) == nil && p != "" {
			pathsToDelete = append(pathsToDelete, p)
		}
	}
	for _, p := range pathsToDelete {
		if err := fileStorage.Delete(ctx, p); err != nil {
			fmt.Printf("Error deleting file %s: %v\n", p, err)
		}
	}

	var shopName string
	_ = database.DB.QueryRow(context.Background(), "SELECT COALESCE(NULLIF(TRIM(shop_name), ''), 'Shop') FROM users WHERE id = $1", claims.UserID).Scan(&shopName)
	msg := "Your print is ready for pickup."
	if shopName != "" {
		msg = "Your print is ready for pickup at " + shopName + "."
	}
	notifications.SendToUser(customerUserID, "Print ready", msg, map[string]string{"type": "print_ready", "file_id": strconv.Itoa(fileID)})

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Print confirmed"})
}

// PrintStartedPrivate sets the whole private order to 'printing' when shopkeeper taps Print (one code = one order).
func PrintStartedPrivate(w http.ResponseWriter, r *http.Request) {
	code := chi.URLParam(r, "code")
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	var role string
	if err := database.DB.QueryRow(context.Background(), "SELECT role FROM users WHERE id = $1", claims.UserID).Scan(&role); err != nil || role != "shopkeeper" {
		http.Error(w, "Only shopkeepers can start prints", http.StatusForbidden)
		return
	}
	// Resolve order: get payment_order_id from file with this code
	var paymentOrderID *int
	_ = database.DB.QueryRow(context.Background(), "SELECT payment_order_id FROM files WHERE unique_code = $1", code).Scan(&paymentOrderID)
	var result pgconn.CommandTag
	var err error
	if paymentOrderID != nil {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'printing' WHERE payment_order_id = $1 AND status = 'uploaded'", *paymentOrderID)
	} else {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'printing' WHERE unique_code = $1 AND status = 'uploaded'", code)
	}
	if err != nil {
		http.Error(w, "Failed to update status", http.StatusInternalServerError)
		return
	}
	if result.RowsAffected() == 0 {
		http.Error(w, "File not found or not in uploaded state", http.StatusNotFound)
		return
	}
	var customerUserID int
	if database.DB.QueryRow(context.Background(), "SELECT user_id FROM files WHERE unique_code = $1", code).Scan(&customerUserID) == nil && customerUserID > 0 {
		var shopName string
		_ = database.DB.QueryRow(context.Background(), "SELECT COALESCE(NULLIF(TRIM(shop_name), ''), 'Shop') FROM users WHERE id = $1", claims.UserID).Scan(&shopName)
		msg := "Your print has started."
		if shopName != "" {
			msg = shopName + " has started printing your job."
		}
		notifications.SendToUser(customerUserID, "Printing started", msg, map[string]string{"type": "printing_started"})
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Print started"})
}

// PrintFailedPrivate clears the whole private order back to 'uploaded' when print fails or times out (one code = one order).
func PrintFailedPrivate(w http.ResponseWriter, r *http.Request) {
	code := chi.URLParam(r, "code")
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	var role string
	if err := database.DB.QueryRow(context.Background(), "SELECT role FROM users WHERE id = $1", claims.UserID).Scan(&role); err != nil || role != "shopkeeper" {
		http.Error(w, "Only shopkeepers can report print failed", http.StatusForbidden)
		return
	}
	var paymentOrderID *int
	_ = database.DB.QueryRow(context.Background(), "SELECT payment_order_id FROM files WHERE unique_code = $1", code).Scan(&paymentOrderID)
	var result pgconn.CommandTag
	var err error
	if paymentOrderID != nil {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'uploaded' WHERE payment_order_id = $1 AND status = 'printing'", *paymentOrderID)
	} else {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'uploaded' WHERE unique_code = $1 AND status = 'printing'", code)
	}
	if err != nil {
		http.Error(w, "Failed to update status", http.StatusInternalServerError)
		return
	}
	if result.RowsAffected() == 0 {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"message": "No change"})
		return
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Print failed recorded"})
}

// ConfirmQueuePrint confirms the whole queue batch (all files in same payment_order_id at this shop).
// One confirm marks all files in the batch as downloaded, deletes them from storage, and notifies customer once.
func ConfirmQueuePrint(w http.ResponseWriter, r *http.Request) {
	fileIDStr := chi.URLParam(r, "fileId")
	fileID, err := strconv.Atoi(fileIDStr)
	if err != nil {
		http.Error(w, "Invalid file ID", http.StatusBadRequest)
		return
	}

	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var shopID int
	var status string
	var paymentOrderID *int
	var customerUserID int
	err = database.DB.QueryRow(context.Background(),
		"SELECT shop_id, status, payment_order_id, user_id FROM files WHERE id = $1", fileID).Scan(&shopID, &status, &paymentOrderID, &customerUserID)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}
	if shopID != claims.UserID {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}
	if status == "withdrawn" {
		http.Error(w, "This print was withdrawn by the customer and can no longer be confirmed", http.StatusGone)
		return
	}
	if status == "downloaded" {
		http.Error(w, "Print already confirmed", http.StatusGone)
		return
	}

	// Ensure payout record exists for this paid order
	if paymentOrderID != nil {
		var paymentAmount float64
		var platformCommission float64
		var orderShopkeeperID *int
		var orderStatus string
		if database.DB.QueryRow(context.Background(),
			`SELECT amount, platform_commission, shopkeeper_id, status FROM payment_orders WHERE id = $1`,
			*paymentOrderID).Scan(&paymentAmount, &platformCommission, &orderShopkeeperID, &orderStatus) == nil && orderStatus == "paid" {
			if orderShopkeeperID == nil {
				shopkeeperAmount := payment.CalculateShopkeeperAmount(paymentAmount, platformCommission)
				_, _ = database.DB.Exec(context.Background(),
					`UPDATE payment_orders SET shopkeeper_id = $1, shopkeeper_amount = $2 WHERE id = $3`,
					claims.UserID, shopkeeperAmount, *paymentOrderID)
				orderShopkeeperID = &claims.UserID
			}
			if orderShopkeeperID != nil && *orderShopkeeperID == claims.UserID {
				shopkeeperAmount := payment.CalculateShopkeeperAmount(paymentAmount, platformCommission)
				_, _ = database.DB.Exec(context.Background(),
					`INSERT INTO shopkeeper_payouts (shopkeeper_id, payment_order_id, amount, status) VALUES ($1, $2, $3, 'pending') ON CONFLICT (shopkeeper_id, payment_order_id) DO NOTHING`,
					claims.UserID, *paymentOrderID, shopkeeperAmount)
			}
		}
	}

	// Update all files in this batch (same payment_order_id and shop) to downloaded
	var result pgconn.CommandTag
	if paymentOrderID != nil {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'downloaded' WHERE payment_order_id = $1 AND shop_id = $2 AND status IN ('uploaded', 'printing')",
			*paymentOrderID, shopID)
	} else {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'downloaded' WHERE id = $1 AND status IN ('uploaded', 'printing')", fileID)
	}
	if err != nil {
		fmt.Printf("Error updating file status: %v\n", err)
		http.Error(w, "Failed to update print status", http.StatusInternalServerError)
		return
	}
	if result.RowsAffected() == 0 {
		http.Error(w, "File not found or already confirmed", http.StatusNotFound)
		return
	}

	// Delete all files in this batch from storage
	ctx := r.Context()
	if paymentOrderID != nil {
		rows, qErr := database.DB.Query(context.Background(),
			"SELECT file_path FROM files WHERE payment_order_id = $1 AND shop_id = $2", *paymentOrderID, shopID)
		if qErr == nil {
			for rows.Next() {
				var p string
				if rows.Scan(&p) == nil && p != "" {
					if err := fileStorage.Delete(ctx, p); err != nil {
						fmt.Printf("Error deleting file %s: %v\n", p, err)
					}
				}
			}
			rows.Close()
		}
	} else {
		var p string
		if database.DB.QueryRow(context.Background(), "SELECT file_path FROM files WHERE id = $1", fileID).Scan(&p) == nil && p != "" {
			_ = fileStorage.Delete(ctx, p)
		}
	}

	normalizeQueuePositions(shopID)

	var shopName string
	_ = database.DB.QueryRow(context.Background(), "SELECT COALESCE(NULLIF(TRIM(shop_name), ''), 'Shop') FROM users WHERE id = $1", claims.UserID).Scan(&shopName)
	msg := "Your print is ready for pickup."
	if shopName != "" {
		msg = "Your print is ready for pickup at " + shopName + "."
	}
	notifications.SendToUser(customerUserID, "Print ready", msg, map[string]string{"type": "print_ready", "file_id": strconv.Itoa(fileID)})

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Print confirmed"})
}

// PrintStartedQueue sets file status to 'printing' when shopkeeper taps Print (disables customer withdraw).
func PrintStartedQueue(w http.ResponseWriter, r *http.Request) {
	fileIDStr := chi.URLParam(r, "fileId")
	fileID, err := strconv.Atoi(fileIDStr)
	if err != nil {
		http.Error(w, "Invalid file ID", http.StatusBadRequest)
		return
	}
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	var shopID int
	err = database.DB.QueryRow(context.Background(),
		"SELECT shop_id FROM files WHERE id = $1", fileID).Scan(&shopID)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}
	if shopID != claims.UserID {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}
	result, err := database.DB.Exec(context.Background(),
		"UPDATE files SET status = 'printing' WHERE id = $1 AND status = 'uploaded'", fileID)
	if err != nil {
		http.Error(w, "Failed to update status", http.StatusInternalServerError)
		return
	}
	if result.RowsAffected() == 0 {
		http.Error(w, "File not found or not in uploaded state", http.StatusNotFound)
		return
	}
	// Mark entire order as printing: all files in the same payment_order_id must be locked
	// so customer cannot withdraw any file in the batch (single order = all files or none).
	var paymentOrderID *int
	if database.DB.QueryRow(context.Background(), "SELECT payment_order_id FROM files WHERE id = $1", fileID).Scan(&paymentOrderID) == nil && paymentOrderID != nil {
		_, _ = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'printing' WHERE payment_order_id = $1 AND status = 'uploaded'", *paymentOrderID)
	}
	var customerUserID int
	if database.DB.QueryRow(context.Background(), "SELECT user_id FROM files WHERE id = $1", fileID).Scan(&customerUserID) == nil && customerUserID > 0 {
		var shopName string
		_ = database.DB.QueryRow(context.Background(), "SELECT COALESCE(NULLIF(TRIM(shop_name), ''), 'Shop') FROM users WHERE id = $1", claims.UserID).Scan(&shopName)
		msg := "Your print has started."
		if shopName != "" {
			msg = shopName + " has started printing your job."
		}
		notifications.SendToUser(customerUserID, "Printing started", msg, map[string]string{"type": "printing_started", "file_id": strconv.Itoa(fileID)})
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Print started"})
}

// PrintFailedQueue clears 'printing' back to 'uploaded' when print fails or times out (re-enables customer withdraw).
func PrintFailedQueue(w http.ResponseWriter, r *http.Request) {
	fileIDStr := chi.URLParam(r, "fileId")
	fileID, err := strconv.Atoi(fileIDStr)
	if err != nil {
		http.Error(w, "Invalid file ID", http.StatusBadRequest)
		return
	}
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	var shopID int
	err = database.DB.QueryRow(context.Background(),
		"SELECT shop_id FROM files WHERE id = $1", fileID).Scan(&shopID)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}
	if shopID != claims.UserID {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}
	result, err := database.DB.Exec(context.Background(),
		"UPDATE files SET status = 'uploaded' WHERE id = $1 AND status = 'printing'", fileID)
	if err != nil {
		http.Error(w, "Failed to update status", http.StatusInternalServerError)
		return
	}
	if result.RowsAffected() == 0 {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"message": "No change"})
		return
	}
	// Revert entire order to 'uploaded' so customer can withdraw the whole batch again
	var paymentOrderID *int
	if database.DB.QueryRow(context.Background(), "SELECT payment_order_id FROM files WHERE id = $1", fileID).Scan(&paymentOrderID) == nil && paymentOrderID != nil {
		_, _ = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'uploaded' WHERE payment_order_id = $1 AND status = 'printing'", *paymentOrderID)
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Print failed recorded"})
}

// CancelOrderByShopkeeperRequest is the body for POST /queue/:fileId/cancel
type CancelOrderByShopkeeperRequest struct {
	Reason string `json:"reason"`
}

// CancelOrderByShopkeeper lets the shopkeeper cancel an order (only when status is 'uploaded', not yet printing).
// Refunds the customer and notifies them with the reason. Entire order (all files in same payment_order) is cancelled.
func CancelOrderByShopkeeper(w http.ResponseWriter, r *http.Request) {
	fileIDStr := chi.URLParam(r, "fileId")
	fileID, err := strconv.Atoi(fileIDStr)
	if err != nil {
		http.Error(w, "Invalid file ID", http.StatusBadRequest)
		return
	}
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var role string
	if database.DB.QueryRow(context.Background(), "SELECT role FROM users WHERE id = $1", claims.UserID).Scan(&role) != nil || role != "shopkeeper" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var req CancelOrderByShopkeeperRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		http.Error(w, "Reason is required", http.StatusBadRequest)
		return
	}
	if len(reason) > 500 {
		reason = reason[:500]
	}

	var shopID int
	var status string
	var paymentOrderID *int
	var customerUserID int
	err = database.DB.QueryRow(context.Background(),
		"SELECT shop_id, status, payment_order_id, user_id FROM files WHERE id = $1", fileID).
		Scan(&shopID, &status, &paymentOrderID, &customerUserID)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}
	if shopID != claims.UserID {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}
	if status != "uploaded" {
		http.Error(w, "Can only cancel orders that have not started printing", http.StatusBadRequest)
		return
	}

	// Determine order scope: all files in same order at this shop
	var fileIDsToCancel []int
	if paymentOrderID != nil {
		// Check no file in this order is already printing
		var printingCount int
		if database.DB.QueryRow(context.Background(),
			"SELECT COUNT(*) FROM files WHERE payment_order_id = $1 AND shop_id = $2 AND status = 'printing'",
			*paymentOrderID, claims.UserID).Scan(&printingCount) == nil && printingCount > 0 {
			http.Error(w, "Cannot cancel: printing has already started for this order", http.StatusBadRequest)
			return
		}
		rows, err := database.DB.Query(context.Background(),
			"SELECT id FROM files WHERE payment_order_id = $1 AND shop_id = $2 AND status = 'uploaded'",
			*paymentOrderID, claims.UserID)
		if err != nil {
			http.Error(w, "Database error", http.StatusInternalServerError)
			return
		}
		for rows.Next() {
			var id int
			if rows.Scan(&id) == nil {
				fileIDsToCancel = append(fileIDsToCancel, id)
			}
		}
		rows.Close()
	} else {
		fileIDsToCancel = []int{fileID}
	}

	if len(fileIDsToCancel) == 0 {
		http.Error(w, "No files in uploaded state to cancel", http.StatusBadRequest)
		return
	}

	// Fetch file paths and delete from storage (same as confirm/withdraw — cancelled orders are not kept on server)
	ctx := r.Context()
	for _, id := range fileIDsToCancel {
		var path string
		if database.DB.QueryRow(context.Background(), "SELECT file_path FROM files WHERE id = $1", id).Scan(&path) == nil && path != "" {
			if err := fileStorage.Delete(ctx, path); err != nil {
				fmt.Printf("Error deleting cancelled file %s: %v\n", path, err)
			}
		}
	}

	// Refund if order was paid (once per payment_order)
	if paymentOrderID != nil {
		var poStatus string
		if database.DB.QueryRow(context.Background(),
			"SELECT status FROM payment_orders WHERE id = $1", *paymentOrderID).Scan(&poStatus) == nil && poStatus == "paid" {
			refundForFile(refundContext{
				UserID:          customerUserID,
				FileID:          fileIDsToCancel[0],
				PaymentOrderID:  *paymentOrderID,
				Reason:          "Order cancelled by shop: " + reason,
			})
		}
	}

	// Mark all files as cancelled
	for _, id := range fileIDsToCancel {
		_, _ = database.DB.Exec(context.Background(),
			`UPDATE files SET status = 'cancelled', cancel_reason = $1, cancelled_at = NOW(), cancelled_by = $2 WHERE id = $3`,
			reason, claims.UserID, id)
	}

	// Notify customer
	notifications.SendToUser(customerUserID, "Order cancelled by shop",
		"The shop cancelled your order. Reason: "+reason,
		map[string]string{"type": "order_cancelled_by_shop", "reason": reason})

	normalizeQueuePositions(claims.UserID)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Order cancelled"})
}

func haversine(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371 // Earth radius in kilometers
	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return R * c
}

func GetShopHistory(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Fetch all files printed by this shop (status='downloaded'), with customer name, file details, and payout/settlement status
	rows, err := database.DB.Query(context.Background(),
		`SELECT f.id, f.unique_code, f.print_type, f.copies, f.num_pages, f.total_cost, f.created_at,
		 f.file_path, f.color_mode, f.paper_size, f.print_mode, f.payment_order_id,
		 COALESCE(NULLIF(TRIM(u.full_name), ''), NULLIF(TRIM(u.email), ''), u.phone, 'Customer') as customer_name,
		 sp.status as payout_status, sp.paid_at as payout_paid_at
		 FROM files f
		 LEFT JOIN users u ON f.user_id = u.id
		 LEFT JOIN payment_orders po ON f.payment_order_id = po.id
		 LEFT JOIN shopkeeper_payouts sp ON sp.payment_order_id = po.id AND sp.shopkeeper_id = f.shop_id
		 WHERE f.shop_id = $1 AND f.status = 'downloaded'
		 ORDER BY f.created_at DESC`, claims.UserID)

	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var history []map[string]interface{}
	for rows.Next() {
		var id, copies, numPages int
		var uniqueCode, printType, customerName string
		var filePath, colorMode, paperSize, printMode *string
		var totalCost float64
		var createdAt time.Time
		var paymentOrderID *int
		var payoutStatus *string
		var payoutPaidAt *time.Time

		if err := rows.Scan(&id, &uniqueCode, &printType, &copies, &numPages, &totalCost, &createdAt,
			&filePath, &colorMode, &paperSize, &printMode, &paymentOrderID, &customerName,
			&payoutStatus, &payoutPaidAt); err != nil {
			continue
		}
		pathStr := ""
		if filePath != nil {
			pathStr = *filePath
		}
		filename := filepath.Base(pathStr)
		if filename == "" || filename == "." {
			filename = uniqueCode
		}
		val := func(s *string) interface{} {
			if s == nil {
				return ""
			}
			return *s
		}
		payoutStatusVal := ""
		if payoutStatus != nil {
			payoutStatusVal = *payoutStatus
		}
		var payoutPaidAtVal interface{}
		if payoutPaidAt != nil {
			payoutPaidAtVal = *payoutPaidAt
		}

		history = append(history, map[string]interface{}{
			"id":              id,
			"code":            uniqueCode,
			"type":            printType,
			"copies":          copies,
			"pages":           numPages,
			"cost":            totalCost,
			"date":            createdAt,
			"customer_name":   customerName,
			"filename":        filename,
			"color_mode":      val(colorMode),
			"paper_size":      val(paperSize),
			"print_mode":      val(printMode),
			"payment_order_id": paymentOrderID,
			"payout_status":   payoutStatusVal,
			"payout_paid_at":  payoutPaidAtVal,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"history": history})
}

// WithdrawPrint withdraws the whole order (all files with same payment_order_id). One fileId identifies the order.
// Refunds once, marks all files in the order as withdrawn, deletes all from storage, normalizes queue for affected shops.
func WithdrawPrint(w http.ResponseWriter, r *http.Request) {
	fileIDStr := chi.URLParam(r, "fileId")
	fileID, err := strconv.Atoi(fileIDStr)
	if err != nil {
		http.Error(w, "Invalid file ID", http.StatusBadRequest)
		return
	}

	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var userID int
	var status string
	var paymentOrderID *int
	err = database.DB.QueryRow(context.Background(),
		"SELECT user_id, status, payment_order_id FROM files WHERE id = $1", fileID).Scan(&userID, &status, &paymentOrderID)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}
	if userID != claims.UserID {
		http.Error(w, "Forbidden: You can only withdraw your own files", http.StatusForbidden)
		return
	}
	if status == "downloaded" {
		http.Error(w, "Cannot withdraw a file that has already been downloaded", http.StatusConflict)
		return
	}
	if status == "printing" {
		http.Error(w, "Cannot withdraw while the print is in progress at the shop", http.StatusConflict)
		return
	}

	if paymentOrderID != nil {
		var anyPrinting bool
		if database.DB.QueryRow(context.Background(),
			"SELECT EXISTS(SELECT 1 FROM files WHERE payment_order_id = $1 AND user_id = $2 AND status = 'printing')", *paymentOrderID, userID).Scan(&anyPrinting) == nil && anyPrinting {
			http.Error(w, "Cannot withdraw: the shop has started printing this order. No refund available.", http.StatusConflict)
			return
		}
	}

	// Refund once per order (refundForFile updates payment_order and all files' payment_status)
	if paymentOrderID != nil {
		refundForFile(refundContext{
			UserID:         userID,
			FileID:         fileID,
			PaymentOrderID: *paymentOrderID,
			Reason:         "Customer withdrawal before printing",
		})
	}

	// Mark all files in this order as withdrawn
	var result pgconn.CommandTag
	if paymentOrderID != nil {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'withdrawn' WHERE payment_order_id = $1 AND user_id = $2 AND status IN ('uploaded', 'printing')",
			*paymentOrderID, userID)
	} else {
		result, err = database.DB.Exec(context.Background(),
			"UPDATE files SET status = 'withdrawn' WHERE id = $1 AND user_id = $2 AND status = 'uploaded'", fileID, userID)
	}
	if err != nil {
		fmt.Printf("Error updating file status to withdrawn: %v\n", err)
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	if result.RowsAffected() == 0 {
		http.Error(w, "Cannot withdraw while the print is in progress at the shop", http.StatusConflict)
		return
	}

	// Collect file paths to delete and distinct shop_ids for queue normalization (before we rely on updated rows)
	var pathsToDelete []string
	var shopIDs []int
	if paymentOrderID != nil {
		rows, qErr := database.DB.Query(context.Background(),
			"SELECT file_path, shop_id FROM files WHERE payment_order_id = $1 AND user_id = $2", *paymentOrderID, userID)
		if qErr == nil {
			seenShop := make(map[int]bool)
			for rows.Next() {
				var p string
				var sid *int
				if rows.Scan(&p, &sid) == nil {
					if p != "" {
						pathsToDelete = append(pathsToDelete, p)
					}
					if sid != nil && !seenShop[*sid] {
						seenShop[*sid] = true
						shopIDs = append(shopIDs, *sid)
					}
				}
			}
			rows.Close()
		}
	} else {
		var p string
		var sid *int
		if database.DB.QueryRow(context.Background(), "SELECT file_path, shop_id FROM files WHERE id = $1", fileID).Scan(&p, &sid) == nil && p != "" {
			pathsToDelete = append(pathsToDelete, p)
			if sid != nil {
				shopIDs = append(shopIDs, *sid)
			}
		}
	}

	ctx := r.Context()
	for _, p := range pathsToDelete {
		if err := fileStorage.Delete(ctx, p); err != nil {
			fmt.Printf("Error deleting file %s: %v\n", p, err)
		}
	}
	for _, sid := range shopIDs {
		normalizeQueuePositions(sid)
	}

	notifications.SendToUser(userID, "Print withdrawn", "Your print job has been withdrawn successfully.", map[string]string{"type": "order_withdrawn", "file_id": strconv.Itoa(fileID)})

	response := map[string]interface{}{
		"message": "Print job withdrawn successfully",
	}
	if paymentOrderID != nil {
		response["refund_processed"] = true
		response["message"] = "Print job withdrawn successfully. Refund has been processed to your original payment method."
	}
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}
