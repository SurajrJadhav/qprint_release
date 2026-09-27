package models

import "time"

// PaymentOrder represents a payment order in the system
type PaymentOrder struct {
	ID               int       `json:"id"`
	UserID           int       `json:"user_id"`
	OrderID          string    `json:"order_id"`          // Razorpay order_id
	PaymentID        *string   `json:"payment_id"`         // Razorpay payment_id
	Amount           float64   `json:"amount"`
	Status           string    `json:"status"`             // 'pending', 'paid', 'failed', 'refunded', 'expired'
	PaymentGateway   string    `json:"payment_gateway"`
	ShopkeeperID     *int      `json:"shopkeeper_id"`      // NULL for private prints
	PlatformCommission float64 `json:"platform_commission"` // e.g., 0.10 for 10%
	ShopkeeperAmount *float64  `json:"shopkeeper_amount"` // Amount to pay shopkeeper
	Copies           int       `json:"copies"`
	PrintMode        string    `json:"print_mode"`
	ColorMode        string    `json:"color_mode"`
	PaperSize        string    `json:"paper_size"`
	PrintType        string    `json:"print_type"`         // 'private' or 'queue'
	Comment          *string   `json:"comment"`
	CreatedAt        time.Time `json:"created_at"`
	PaidAt           *time.Time `json:"paid_at"`
	ExpiresAt        *time.Time `json:"expires_at"`
	FileID           *int       `json:"file_id"`
}

// CreatePaymentOrderRequest represents the request to create a payment order
type CreatePaymentOrderRequest struct {
	Amount             float64  `json:"amount"`
	ShopkeeperID       *int     `json:"shopkeeper_id"`        // Required for queue prints
	Copies             int      `json:"copies"`
	PrintMode          string   `json:"print_mode"`
	ColorMode          string   `json:"color_mode"`
	PaperSize          string   `json:"paper_size"`
	PrintType          string   `json:"print_type"`           // 'private' or 'queue'
	Comment            *string  `json:"comment"`
	PlatformCommission *float64 `json:"platform_commission"`  // Optional, defaults to 0
	UseWallet          bool     `json:"use_wallet"`           // If true, use wallet balance when sufficient
	WalletAmount       *float64 `json:"wallet_amount"`        // Optional: for hybrid, amount to take from wallet (server can compute)
}

// PaymentOrderResponse represents the response after creating a payment order
type PaymentOrderResponse struct {
	OrderID    string  `json:"order_id"`
	PaymentID  *string `json:"payment_id"`
	Amount     float64 `json:"amount"`
	Status     string  `json:"status"`
	PaymentLink string `json:"payment_link,omitempty"` // For payment links
	KeyID      string  `json:"key_id,omitempty"`       // Razorpay key for frontend
}

// ShopkeeperPayout represents a payout to a shopkeeper
type ShopkeeperPayout struct {
	ID              int        `json:"id"`
	ShopkeeperID    int        `json:"shopkeeper_id"`
	PaymentOrderID  int        `json:"payment_order_id"`
	Amount          float64    `json:"amount"`
	Status          string     `json:"status"` // 'pending', 'paid', 'failed'
	PayoutMethod    *string    `json:"payout_method"`
	PayoutReference *string    `json:"payout_reference"`
	PaidAt          *time.Time `json:"paid_at"`
	CreatedAt       time.Time  `json:"created_at"`
}

// CalculateCostRequest represents request to calculate cost before payment
type CalculateCostRequest struct {
	File     interface{} `json:"-"` // File will be in multipart form
	Copies   int        `json:"copies"`
	PrintMode string    `json:"print_mode"`
	ColorMode string    `json:"color_mode"`
	PaperSize string    `json:"paper_size"`
}

// CalculateCostResponse represents the calculated cost
type CalculateCostResponse struct {
	NumPages   int     `json:"num_pages"`
	Copies     int     `json:"copies"`
	TotalCost  float64 `json:"total_cost"`
	CostPerPage float64 `json:"cost_per_page"`
}
