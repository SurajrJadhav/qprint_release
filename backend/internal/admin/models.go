package admin

import "time"

// DashboardStats represents admin dashboard statistics
type DashboardStats struct {
	TotalUsers       int     `json:"total_users"`
	TotalCustomers   int     `json:"total_customers"`
	TotalShopkeepers int     `json:"total_shopkeepers"`
	TotalOrders      int     `json:"total_orders"`
	TotalRevenue     float64 `json:"total_revenue"`
	PendingPayouts   float64 `json:"pending_payouts"`
	PaidPayouts      float64 `json:"paid_payouts"`
	ActiveOrders     int     `json:"active_orders"`
	FailedOrders     int     `json:"failed_orders"`
}

// UserListResponse represents paginated user list
type UserListResponse struct {
	Users      []UserDetail `json:"users"`
	Total      int          `json:"total"`
	Page       int          `json:"page"`
	PageSize   int          `json:"page_size"`
	TotalPages int          `json:"total_pages"`
}

// UserDetail represents detailed user information for admin
type UserDetail struct {
	ID           int       `json:"id"`
	FullName     *string   `json:"full_name,omitempty"`
	Email        *string   `json:"email,omitempty"`
	Phone        *string   `json:"phone,omitempty"`
	ShopName     *string   `json:"shop_name,omitempty"`
	Role         string    `json:"role"`
	Lat          *float64  `json:"lat,omitempty"`
	Long         *float64  `json:"long,omitempty"`
	Address      *string   `json:"address,omitempty"`
	IsOpen       bool      `json:"is_open"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
	TotalOrders  int       `json:"total_orders"`
	TotalSpent   float64   `json:"total_spent,omitempty"`   // For customers
	TotalEarned  float64   `json:"total_earned,omitempty"`   // For shopkeepers
}

// OrderListResponse represents paginated order list
type OrderListResponse struct {
	Orders     []OrderDetail `json:"orders"`
	Total      int           `json:"total"`
	Page       int           `json:"page"`
	PageSize   int           `json:"page_size"`
	TotalPages int           `json:"total_pages"`
}

// OrderDetail represents detailed order information for admin
type OrderDetail struct {
	ID                int       `json:"id"`
	UserID            int       `json:"user_id"`
	CustomerName      string    `json:"customer_name"`
	OrderID           string    `json:"order_id"`
	PaymentID         *string   `json:"payment_id,omitempty"`
	Amount            float64   `json:"amount"`
	Status            string    `json:"status"`
	ShopkeeperID      *int      `json:"shopkeeper_id,omitempty"`
	ShopkeeperName    *string   `json:"shopkeeper_name,omitempty"`
	PlatformCommission float64  `json:"platform_commission"`
	ShopkeeperAmount  *float64  `json:"shopkeeper_amount,omitempty"`
	PrintType         string    `json:"print_type"`
	Copies            int       `json:"copies"`
	PrintMode         string    `json:"print_mode"`
	ColorMode         string    `json:"color_mode"`
	PaperSize         string    `json:"paper_size"`
	FileID            *int      `json:"file_id,omitempty"`
	CreatedAt         time.Time `json:"created_at"`
	PaidAt            *time.Time `json:"paid_at,omitempty"`
}

// PayoutListResponse represents paginated payout list
type PayoutListResponse struct {
	Payouts   []PayoutDetail `json:"payouts"`
	Total     int            `json:"total"`
	Page      int            `json:"page"`
	PageSize  int            `json:"page_size"`
	TotalPages int           `json:"total_pages"`
	Summary   *PayoutSummary `json:"summary,omitempty"`
}

// PayoutSummary is summary counts/amounts for current filter
type PayoutSummary struct {
	TotalPendingCount   int     `json:"total_pending_count"`
	TotalPendingAmount  float64 `json:"total_pending_amount"`
	TotalPaidCount      int     `json:"total_paid_count"`
	TotalPaidAmount     float64 `json:"total_paid_amount"`
}

// PayoutDetail represents detailed payout information for admin
type PayoutDetail struct {
	ID              int        `json:"id"`
	ShopkeeperID    int        `json:"shopkeeper_id"`
	ShopkeeperName  string     `json:"shopkeeper_name"`
	PaymentOrderID  int        `json:"payment_order_id"`
	OrderID         string     `json:"order_id"`
	Amount          float64    `json:"amount"`
	Status          string     `json:"status"`
	PayoutMethod    *string    `json:"payout_method,omitempty"`
	PayoutReference *string    `json:"payout_reference,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	PaidAt          *time.Time `json:"paid_at,omitempty"`
	FailedAt        *time.Time `json:"failed_at,omitempty"`
	FailureReason   *string    `json:"failure_reason,omitempty"`
}

// DeleteAccountRequest represents account deletion request
type DeleteAccountRequest struct {
	UserID int    `json:"user_id"`
	Reason string `json:"reason,omitempty"`
}
