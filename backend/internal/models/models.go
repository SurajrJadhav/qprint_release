package models

import "time"

type User struct {
	ID           int       `json:"id"`
	Username     string    `json:"-"` // internal DB column only; not exposed in API
	FullName     *string   `json:"full_name,omitempty"`
	Email        *string   `json:"email,omitempty"`
	Phone        *string   `json:"phone,omitempty"`
	ShopName     *string   `json:"shop_name,omitempty"`
	PasswordHash string    `json:"-"`
	Role         string    `json:"role"` // 'customer' or 'shopkeeper'
	Lat          float64   `json:"lat,omitempty"`
	Long         float64   `json:"long,omitempty"`
	Address      string    `json:"address,omitempty"`
	IsOpen       bool      `json:"is_open"`
	ShopCode     *int      `json:"shop_code,omitempty"` // 6-digit unique code for shop (100000-999999)
	ReferralCode *string   `json:"referral_code,omitempty"`
	CreatedAt    time.Time `json:"created_at,omitempty"`
	UpdatedAt    time.Time `json:"updated_at,omitempty"`
}

type File struct {
	ID            int       `json:"id"`
	UserID        int       `json:"user_id"`
	FilePath      string    `json:"file_path"`
	UniqueCode    string    `json:"unique_code"`
	Status        string    `json:"status"`
	CreatedAt     time.Time `json:"created_at"`
	PrintType     string    `json:"print_type"`
	Copies        int       `json:"copies"`
	PrintMode     string    `json:"print_mode"`
	ColorMode     string    `json:"color_mode"`
	PaperSize     string    `json:"paper_size"`
	NumPages      int       `json:"num_pages"`
	TotalCost     float64   `json:"total_cost"`
	ShopID        *int      `json:"shop_id,omitempty"`
	QueuePosition *int      `json:"queue_position,omitempty"`
	Comment       *string   `json:"comment,omitempty"`
}

type LoginRequest struct {
	// Login accepts email or mobile (phone).
	Login    string `json:"login"`
	Password string `json:"password"`
}

type RegisterRequest struct {
	FullName     string   `json:"full_name"`
	Email        string   `json:"email"`
	Phone        string   `json:"phone"`
	Password     string   `json:"password"`
	Role         string   `json:"role"`
	ShopName     string   `json:"shop_name,omitempty"` // Required for shopkeeper
	Lat          *float64 `json:"lat"`
	Long         *float64 `json:"long"`
	Address      string   `json:"address,omitempty"`
	ReferralCode string   `json:"referral_code,omitempty"` // Optional; only customers
	SignupToken  string   `json:"signup_token,omitempty"`  // Required (unless SKIP_SIGNUP_OTP); from POST /register/verify-otp
}

type LoginResponse struct {
	Token       string `json:"token"`
	Role        string `json:"role"`
	DisplayName string `json:"display_name"`
}

type UploadRequest struct {
	PrintType string `json:"print_type"` // "private" or "queue"
	Copies    int    `json:"copies"`
	PrintMode string `json:"print_mode"` // "single" or "double"
	ColorMode string `json:"color_mode"` // "bw" or "color"
	PaperSize string `json:"paper_size"` // "A4", "Letter", etc.
	ShopID    *int   `json:"shop_id,omitempty"`
}

type UploadResponse struct {
	Code          string  `json:"code,omitempty"`
	FileID        int     `json:"file_id"`
	NumPages      int     `json:"num_pages"`
	TotalCost     float64 `json:"total_cost"`
	QueuePosition *int    `json:"queue_position,omitempty"`
}

type QueueFile struct {
	ID            int       `json:"id"`
	CustomerName  string    `json:"customer_name"`
	Filename      string    `json:"filename"`
	Copies        int       `json:"copies"`
	PrintMode     string    `json:"print_mode"`
	ColorMode     string    `json:"color_mode"`
	PaperSize     string    `json:"paper_size"`
	NumPages      int       `json:"num_pages"`
	TotalCost     float64   `json:"total_cost"`
	QueuePosition int       `json:"queue_position"`
	CreatedAt     time.Time `json:"created_at"`
	Comment       *string   `json:"comment,omitempty"`
}

type UpdateProfileRequest struct {
	Password        string `json:"password,omitempty"`
	CurrentPassword string `json:"current_password,omitempty"` // required when changing password
	Address         string `json:"address"`
	FullName        string `json:"full_name,omitempty"`
	Email           string `json:"email,omitempty"`
	Phone           string `json:"phone,omitempty"`
	ShopName        string `json:"shop_name,omitempty"` // shopkeeper only
}

// UpdateShopPricingRequest is used by shopkeepers to set per-page rates and optional double-sided factor.
// All fields optional; nil/omit to leave unchanged. Sent as JSON for PATCH /shopkeeper/pricing.
type UpdateShopPricingRequest struct {
	PricePerPageBW    *float64 `json:"price_per_page_bw,omitempty"`    // non-negative, max 9999.99
	PricePerPageColor *float64 `json:"price_per_page_color,omitempty"` // non-negative, max 9999.99
	DoubleSidedFactor *float64 `json:"double_sided_factor,omitempty"`  // in (0, 1], e.g. 0.5 = half price
}

type ForgotPasswordRequest struct {
	Email string `json:"email"`
}

type ResetPasswordRequest struct {
	Token    string `json:"token"`
	Password string `json:"password"`
}

// ReferralSummary is the response for GET /referral/summary
type ReferralSummary struct {
	TotalReferred   int     `json:"total_referred"`
	TotalCredited   int     `json:"total_credited"`
	TotalEarnings   float64 `json:"total_earnings"`
	PendingCount    int     `json:"pending_count"`
}

// ReferralHistoryItem is one row for GET /referral/history
type ReferralHistoryItem struct {
	ID           int        `json:"id"`
	Status       string     `json:"status"`
	Amount       float64    `json:"amount,omitempty"`
	CreditedAt   *time.Time `json:"credited_at,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
}
