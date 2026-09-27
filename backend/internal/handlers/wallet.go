package handlers

import (
	"backend/internal/auth"
	"backend/internal/database"
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"
)

// GetWalletBalance returns the current user's wallet balance
func GetWalletBalance(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var balance float64
	err := database.DB.QueryRow(context.Background(),
		"SELECT COALESCE(wallet_balance, 0) FROM users WHERE id = $1", claims.UserID).Scan(&balance)
	if err != nil {
		log.Printf("GetWalletBalance: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"balance": balance})
}

// WalletTransaction represents a single wallet transaction for API response
type WalletTransaction struct {
	ID               int       `json:"id"`
	TransactionType  string    `json:"transaction_type"`
	Amount           float64   `json:"amount"`
	BalanceAfter     float64   `json:"balance_after"`
	Status           string    `json:"status"`
	Description      *string   `json:"description,omitempty"`
	CreatedAt        time.Time `json:"created_at"`
}

// GetWalletTransactions returns paginated wallet transactions for the current user
func GetWalletTransactions(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit < 1 || limit > 100 {
		limit = 50
	}
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if offset < 0 {
		offset = 0
	}
	if offset > 10000 {
		offset = 10000
	}

	rows, err := database.DB.Query(context.Background(),
		`SELECT id, transaction_type, amount, balance_after, status, description, created_at
		 FROM wallet_transactions WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
		claims.UserID, limit, offset)
	if err != nil {
		log.Printf("GetWalletTransactions: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var transactions []WalletTransaction
	for rows.Next() {
		var t WalletTransaction
		var desc *string
		err := rows.Scan(&t.ID, &t.TransactionType, &t.Amount, &t.BalanceAfter, &t.Status, &desc, &t.CreatedAt)
		if err != nil {
			continue
		}
		t.Description = desc
		transactions = append(transactions, t)
	}

	var total int
	_ = database.DB.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM wallet_transactions WHERE user_id = $1", claims.UserID).Scan(&total)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"transactions": transactions,
		"total":        total,
	})
}

// TopupRequest is the body for wallet top-up
type TopupRequest struct {
	Amount float64 `json:"amount"`
}

const minTopup = 10.0
const maxTopup = 10000.0

// TopupWallet creates a Razorpay order for adding money to wallet.
// Security: auth required (middleware), amount bounded [10, 10000]; wallet_transactions record audit after webhook capture.
func TopupWallet(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	if razorpayClient == nil {
		http.Error(w, "Payment service not configured", http.StatusServiceUnavailable)
		return
	}

	var req TopupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	// Reject NaN, Inf, and out-of-range to prevent abuse
	if req.Amount != req.Amount || req.Amount < minTopup || req.Amount > maxTopup {
		http.Error(w, "Amount must be between 10 and 10000", http.StatusBadRequest)
		return
	}

	receipt := "wallet_topup_" + strconv.Itoa(claims.UserID) + "_" + strconv.FormatInt(time.Now().Unix(), 10)
	notes := map[string]string{
		"user_id": strconv.Itoa(claims.UserID),
		"type":    "wallet_topup",
	}
	razorpayOrder, err := razorpayClient.CreateOrder(req.Amount, receipt, notes)
	if err != nil {
		log.Printf("TopupWallet: Razorpay error: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	_, err = database.DB.Exec(context.Background(),
		`INSERT INTO wallet_topup_orders (user_id, order_id, amount, status) VALUES ($1, $2, $3, 'pending')`,
		claims.UserID, razorpayOrder.ID, req.Amount)
	if err != nil {
		log.Printf("TopupWallet: insert topup order: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"order_id": razorpayOrder.ID,
		"key_id":  razorpayClient.KeyID,
		"amount":  req.Amount,
	})
}
