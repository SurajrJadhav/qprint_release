package admin

import (
	"context"
	"database/sql"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"backend/internal/auth"
	"backend/internal/database"
	"backend/internal/notifications"

	"github.com/jackc/pgx/v5/pgconn"
)

// AdminMeResponse is returned by GET /admin/me
type AdminMeResponse struct {
	DisplayName     string `json:"display_name"`
	Email           string `json:"email"` // empty if not set
	FullName        string `json:"full_name"`
	Email2FAEnabled bool   `json:"email_2fa_enabled"`
}

// GetAdminMe returns the current admin's account info (for display on dashboard).
func GetAdminMe(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok || claims.Role != "admin" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var out AdminMeResponse
	err := database.DB.QueryRow(context.Background(),
		`SELECT COALESCE(NULLIF(TRIM(full_name), ''), NULLIF(TRIM(email), ''), 'Admin'), COALESCE(TRIM(email), ''), COALESCE(TRIM(full_name), ''), COALESCE(email_2fa_enabled, false) FROM users WHERE id = $1`,
		claims.UserID).Scan(&out.DisplayName, &out.Email, &out.FullName, &out.Email2FAEnabled)
	if err != nil {
		log.Printf("GetAdminMe: %v", err)
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(out)
}

// UpdateAdminMeRequest is the body for PUT /admin/me
type UpdateAdminMeRequest struct {
	Email    string `json:"email"`
	FullName string `json:"full_name"`
}

var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

// UpdateAdminMe updates the current admin's email and/or full name.
func UpdateAdminMe(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok || claims.Role != "admin" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var req UpdateAdminMeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	email := strings.TrimSpace(req.Email)

	// If email is provided, validate format and uniqueness
	if email != "" {
		if !emailRegex.MatchString(email) {
			http.Error(w, "Invalid email format", http.StatusBadRequest)
			return
		}
		var otherID int
		err := database.DB.QueryRow(context.Background(),
			"SELECT id FROM users WHERE LOWER(TRIM(email)) = LOWER($1) AND id != $2",
			email, claims.UserID).Scan(&otherID)
		if err == nil {
			http.Error(w, "This email is already in use by another account", http.StatusConflict)
			return
		}
	}

	// Update only non-empty fields; empty email clears it, empty full_name clears it
	_, err := database.DB.Exec(context.Background(),
		`UPDATE users SET email = NULLIF(TRIM($1), ''), full_name = NULLIF(TRIM($2), ''), updated_at = NOW() WHERE id = $3`,
		req.Email, req.FullName, claims.UserID)
	if err != nil {
		log.Printf("UpdateAdminMe: %v", err)
		http.Error(w, "Failed to update profile", http.StatusInternalServerError)
		return
	}

	LogAdmin(claims.UserID, "admin_profile_updated", "", "")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Profile updated successfully"})
}

// GetDashboardStats returns admin dashboard statistics
func GetDashboardStats(w http.ResponseWriter, r *http.Request) {
	stats := DashboardStats{}

	// Get user counts
	err := database.DB.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM users").Scan(&stats.TotalUsers)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	err = database.DB.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM users WHERE role = 'customer'").Scan(&stats.TotalCustomers)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	err = database.DB.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM users WHERE role = 'shopkeeper'").Scan(&stats.TotalShopkeepers)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Get order counts
	err = database.DB.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM payment_orders").Scan(&stats.TotalOrders)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	err = database.DB.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM payment_orders WHERE status = 'paid'").Scan(&stats.ActiveOrders)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	err = database.DB.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM payment_orders WHERE status = 'failed'").Scan(&stats.FailedOrders)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Get revenue
	err = database.DB.QueryRow(context.Background(),
		"SELECT COALESCE(SUM(amount), 0) FROM payment_orders WHERE status = 'paid'").Scan(&stats.TotalRevenue)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Get payout stats
	err = database.DB.QueryRow(context.Background(),
		"SELECT COALESCE(SUM(amount), 0) FROM shopkeeper_payouts WHERE status = 'pending'").Scan(&stats.PendingPayouts)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	err = database.DB.QueryRow(context.Background(),
		"SELECT COALESCE(SUM(amount), 0) FROM shopkeeper_payouts WHERE status = 'paid'").Scan(&stats.PaidPayouts)
	if err != nil {
		log.Printf("GetDashboardStats: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

// GetUsers returns paginated list of users
func GetUsers(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page < 1 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	role := r.URL.Query().Get("role")
	search := r.URL.Query().Get("search")

	offset := (page - 1) * pageSize

	var query string
	var args []interface{}

	if role != "" && search != "" {
		query = `
			SELECT id, full_name, email, phone, shop_name, role, lat, long, address, is_open, created_at, updated_at
			FROM users
			WHERE role = $1 AND (full_name ILIKE $2 OR email ILIKE $2 OR phone ILIKE $2 OR shop_name ILIKE $2)
			ORDER BY created_at DESC
			LIMIT $3 OFFSET $4`
		args = []interface{}{role, "%" + search + "%", pageSize, offset}
	} else if role != "" {
		query = `
			SELECT id, full_name, email, phone, shop_name, role, lat, long, address, is_open, created_at, updated_at
			FROM users
			WHERE role = $1
			ORDER BY created_at DESC
			LIMIT $2 OFFSET $3`
		args = []interface{}{role, pageSize, offset}
	} else if search != "" {
		query = `
			SELECT id, full_name, email, phone, shop_name, role, lat, long, address, is_open, created_at, updated_at
			FROM users
			WHERE full_name ILIKE $1 OR email ILIKE $1 OR phone ILIKE $1 OR shop_name ILIKE $1
			ORDER BY created_at DESC
			LIMIT $2 OFFSET $3`
		args = []interface{}{"%" + search + "%", pageSize, offset}
	} else {
		query = `
			SELECT id, full_name, email, phone, shop_name, role, lat, long, address, is_open, created_at, updated_at
			FROM users
			ORDER BY created_at DESC
			LIMIT $1 OFFSET $2`
		args = []interface{}{pageSize, offset}
	}

	rows, err := database.DB.Query(context.Background(), query, args...)
	if err != nil {
		log.Printf("GetUsers: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var users []UserDetail
	for rows.Next() {
		var user UserDetail
		var address sql.NullString
		err := rows.Scan(
			&user.ID, &user.FullName, &user.Email, &user.Phone,
			&user.ShopName, &user.Role, &user.Lat, &user.Long, &address,
			&user.IsOpen, &user.CreatedAt, &user.UpdatedAt,
		)
		if err != nil {
			log.Printf("GetUsers: scan: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}
		if address.Valid {
			user.Address = &address.String
		}

		// Get order stats for this user
		if user.Role == "customer" {
			database.DB.QueryRow(context.Background(),
				"SELECT COUNT(*), COALESCE(SUM(amount), 0) FROM payment_orders WHERE user_id = $1 AND status = 'paid'",
				user.ID).Scan(&user.TotalOrders, &user.TotalSpent)
		} else if user.Role == "shopkeeper" {
			database.DB.QueryRow(context.Background(),
				"SELECT COUNT(*), COALESCE(SUM(amount), 0) FROM shopkeeper_payouts WHERE shopkeeper_id = $1 AND status = 'paid'",
				user.ID).Scan(&user.TotalOrders, &user.TotalEarned)
		}

		users = append(users, user)
	}

	// Get total count
	var total int
	var countQuery string
	var countArgs []interface{}
	if role != "" && search != "" {
		countQuery = "SELECT COUNT(*) FROM users WHERE role = $1 AND (full_name ILIKE $2 OR email ILIKE $2 OR phone ILIKE $2 OR shop_name ILIKE $2)"
		countArgs = []interface{}{role, "%" + search + "%"}
	} else if role != "" {
		countQuery = "SELECT COUNT(*) FROM users WHERE role = $1"
		countArgs = []interface{}{role}
	} else if search != "" {
		countQuery = "SELECT COUNT(*) FROM users WHERE full_name ILIKE $1 OR email ILIKE $1 OR phone ILIKE $1 OR shop_name ILIKE $1"
		countArgs = []interface{}{"%" + search + "%"}
	} else {
		countQuery = "SELECT COUNT(*) FROM users"
		countArgs = []interface{}{}
	}

	err = database.DB.QueryRow(context.Background(), countQuery, countArgs...).Scan(&total)
	if err != nil {
		log.Printf("GetUsers: count: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	totalPages := (total + pageSize - 1) / pageSize

	response := UserListResponse{
		Users:      users,
		Total:      total,
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// GetUserDetails returns detailed information about a specific user
func GetUserDetails(w http.ResponseWriter, r *http.Request) {
	userIDStr := r.URL.Query().Get("user_id")
	userID, err := strconv.Atoi(userIDStr)
	if err != nil {
		http.Error(w, "Invalid user_id", http.StatusBadRequest)
		return
	}

	var user UserDetail
	var address sql.NullString
	err = database.DB.QueryRow(context.Background(),
		`SELECT id, full_name, email, phone, shop_name, role, lat, long, address, is_open, created_at, updated_at
		 FROM users WHERE id = $1`, userID).Scan(
		&user.ID, &user.FullName, &user.Email, &user.Phone,
		&user.ShopName, &user.Role, &user.Lat, &user.Long, &address,
		&user.IsOpen, &user.CreatedAt, &user.UpdatedAt,
	)
	if address.Valid {
		user.Address = &address.String
	}

	if err == sql.ErrNoRows {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}
	if err != nil {
		log.Printf("GetUserDetails: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Get order stats
	if user.Role == "customer" {
		database.DB.QueryRow(context.Background(),
			"SELECT COUNT(*), COALESCE(SUM(amount), 0) FROM payment_orders WHERE user_id = $1 AND status = 'paid'",
			user.ID).Scan(&user.TotalOrders, &user.TotalSpent)
	} else if user.Role == "shopkeeper" {
		database.DB.QueryRow(context.Background(),
			"SELECT COUNT(*), COALESCE(SUM(amount), 0) FROM shopkeeper_payouts WHERE shopkeeper_id = $1 AND status = 'paid'",
			user.ID).Scan(&user.TotalOrders, &user.TotalEarned)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

// GetOrders returns paginated list of orders
func GetOrders(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page < 1 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	status := r.URL.Query().Get("status")
	userIDStr := r.URL.Query().Get("user_id")
	shopkeeperIDStr := r.URL.Query().Get("shopkeeper_id")
	shopkeeperID, _ := strconv.Atoi(shopkeeperIDStr)
	hasShopkeeper := shopkeeperIDStr != "" && shopkeeperID > 0
	pendingAtShop := r.URL.Query().Get("pending_at_shop") == "true"

	offset := (page - 1) * pageSize

	var query string
	var args []interface{}

	baseQuery := `
		SELECT po.id, COALESCE(po.user_id, 0), COALESCE(NULLIF(TRIM(u.full_name), ''), NULLIF(TRIM(u.email), ''), ''), po.order_id, po.payment_id, po.amount, po.status,
		       po.shopkeeper_id, COALESCE(NULLIF(TRIM(sk.shop_name), ''), NULLIF(TRIM(sk.full_name), ''), '') as shopkeeper_name, po.platform_commission, po.shopkeeper_amount,
		       po.print_type, po.copies, po.print_mode, po.color_mode, po.paper_size, po.file_id,
		       po.created_at, po.paid_at
		FROM payment_orders po
		LEFT JOIN users u ON po.user_id = u.id
		LEFT JOIN users sk ON po.shopkeeper_id = sk.id
	`

	pendingAtShopCondition := ` po.status = 'paid' AND EXISTS (SELECT 1 FROM files f WHERE f.payment_order_id = po.id AND f.status IN ('uploaded', 'printing')) `

	if pendingAtShop && hasShopkeeper {
		query = baseQuery + ` WHERE ` + pendingAtShopCondition + ` AND po.shopkeeper_id = $1
			ORDER BY po.created_at ASC
			LIMIT $2 OFFSET $3`
		args = []interface{}{shopkeeperID, pageSize, offset}
	} else if pendingAtShop {
		// Orders paid but not yet completed at shop (files still uploaded/printing). Order by oldest first.
		query = baseQuery + ` WHERE ` + pendingAtShopCondition + `
			ORDER BY po.created_at ASC
			LIMIT $1 OFFSET $2`
		args = []interface{}{pageSize, offset}
	} else if status != "" && userIDStr != "" {
		userID, _ := strconv.Atoi(userIDStr)
		query = baseQuery + ` WHERE po.status = $1 AND po.user_id = $2
			ORDER BY po.created_at DESC
			LIMIT $3 OFFSET $4`
		args = []interface{}{status, userID, pageSize, offset}
	} else if status != "" && hasShopkeeper {
		query = baseQuery + ` WHERE po.status = $1 AND po.shopkeeper_id = $2
			ORDER BY po.created_at DESC
			LIMIT $3 OFFSET $4`
		args = []interface{}{status, shopkeeperID, pageSize, offset}
	} else if status != "" {
		query = baseQuery + ` WHERE po.status = $1
			ORDER BY po.created_at DESC
			LIMIT $2 OFFSET $3`
		args = []interface{}{status, pageSize, offset}
	} else if userIDStr != "" {
		userID, _ := strconv.Atoi(userIDStr)
		query = baseQuery + ` WHERE po.user_id = $1
			ORDER BY po.created_at DESC
			LIMIT $2 OFFSET $3`
		args = []interface{}{userID, pageSize, offset}
	} else if hasShopkeeper {
		query = baseQuery + ` WHERE po.shopkeeper_id = $1
			ORDER BY po.created_at DESC
			LIMIT $2 OFFSET $3`
		args = []interface{}{shopkeeperID, pageSize, offset}
	} else {
		query = baseQuery + ` ORDER BY po.created_at DESC
			LIMIT $1 OFFSET $2`
		args = []interface{}{pageSize, offset}
	}

	rows, err := database.DB.Query(context.Background(), query, args...)
	if err != nil {
		log.Printf("GetOrders: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var orders []OrderDetail
	for rows.Next() {
		var order OrderDetail
		err := rows.Scan(
			&order.ID, &order.UserID, &order.CustomerName, &order.OrderID, &order.PaymentID,
			&order.Amount, &order.Status, &order.ShopkeeperID, &order.ShopkeeperName,
			&order.PlatformCommission, &order.ShopkeeperAmount, &order.PrintType,
			&order.Copies, &order.PrintMode, &order.ColorMode, &order.PaperSize,
			&order.FileID, &order.CreatedAt, &order.PaidAt,
		)
		if err != nil {
			log.Printf("GetOrders: scan: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}
		orders = append(orders, order)
	}

	// Get total count
	var total int
	var countQuery string
	var countArgs []interface{}
	if pendingAtShop && hasShopkeeper {
		countQuery = "SELECT COUNT(*) FROM payment_orders po WHERE " + pendingAtShopCondition + " AND po.shopkeeper_id = $1"
		countArgs = []interface{}{shopkeeperID}
	} else if pendingAtShop {
		countQuery = "SELECT COUNT(*) FROM payment_orders po WHERE " + pendingAtShopCondition
		countArgs = []interface{}{}
	} else if status != "" && userIDStr != "" {
		userID, _ := strconv.Atoi(userIDStr)
		countQuery = "SELECT COUNT(*) FROM payment_orders WHERE status = $1 AND user_id = $2"
		countArgs = []interface{}{status, userID}
	} else if status != "" && hasShopkeeper {
		countQuery = "SELECT COUNT(*) FROM payment_orders WHERE status = $1 AND shopkeeper_id = $2"
		countArgs = []interface{}{status, shopkeeperID}
	} else if status != "" {
		countQuery = "SELECT COUNT(*) FROM payment_orders WHERE status = $1"
		countArgs = []interface{}{status}
	} else if userIDStr != "" {
		userID, _ := strconv.Atoi(userIDStr)
		countQuery = "SELECT COUNT(*) FROM payment_orders WHERE user_id = $1"
		countArgs = []interface{}{userID}
	} else if hasShopkeeper {
		countQuery = "SELECT COUNT(*) FROM payment_orders WHERE shopkeeper_id = $1"
		countArgs = []interface{}{shopkeeperID}
	} else {
		countQuery = "SELECT COUNT(*) FROM payment_orders"
		countArgs = []interface{}{}
	}

	err = database.DB.QueryRow(context.Background(), countQuery, countArgs...).Scan(&total)
	if err != nil {
		log.Printf("GetOrders: count: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	totalPages := (total + pageSize - 1) / pageSize

	response := OrderListResponse{
		Orders:     orders,
		Total:      total,
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// payoutDateRange returns fromDate, toDate (inclusive) from query params. Supports from_date, to_date (ISO) or period (this_week, this_month, last_week, last_month).
func payoutDateRange(r *http.Request) (fromDate, toDate *time.Time) {
	period := r.URL.Query().Get("period")
	fromStr := r.URL.Query().Get("from_date")
	toStr := r.URL.Query().Get("to_date")
	now := time.Now()

	if period != "" {
		var from, to time.Time
		switch period {
		case "this_week":
			// Monday 00:00 of current week to Sunday 23:59
			weekday := int(now.Weekday()) - 1 // Mon=0, Sun=6
			if weekday < 0 {
				weekday = 6
			}
			from = time.Date(now.Year(), now.Month(), now.Day()-weekday, 0, 0, 0, 0, now.Location())
			to = from.AddDate(0, 0, 6)
		case "last_week":
			weekday := int(now.Weekday()) - 1
			if weekday < 0 {
				weekday = 6
			}
			from = time.Date(now.Year(), now.Month(), now.Day()-weekday-7, 0, 0, 0, 0, now.Location())
			to = from.AddDate(0, 0, 6)
		case "this_month":
			from = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
			to = from.AddDate(0, 1, -1)
		case "last_month":
			from = time.Date(now.Year(), now.Month()-1, 1, 0, 0, 0, 0, now.Location())
			to = from.AddDate(0, 1, -1)
		default:
			return nil, nil
		}
		fromDate = &from
		toDate = &to
		return
	}
	if fromStr != "" && toStr != "" {
		from, err1 := time.Parse("2006-01-02", fromStr)
		to, err2 := time.Parse("2006-01-02", toStr)
		if err1 == nil && err2 == nil && !from.After(to) {
			fromDate = &from
			toDate = &to
		}
	}
	return
}

// GetPayouts returns paginated list of payouts.
// Query params: page, page_size, status, shopkeeper_id, from_date, to_date (ISO), period (this_week|this_month|last_week|last_month).
// Response includes summary (total_pending_count/amount, total_paid_count/amount) for the current filter when date range is set.
func GetPayouts(w http.ResponseWriter, r *http.Request) {
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page < 1 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	status := r.URL.Query().Get("status")
	shopkeeperIDStr := r.URL.Query().Get("shopkeeper_id")
	fromDate, toDate := payoutDateRange(r)

	// Backfill missing payouts for this shop
	if shopkeeperIDStr != "" {
		shopkeeperID, _ := strconv.Atoi(shopkeeperIDStr)
		_, _ = database.DB.Exec(context.Background(),
			`UPDATE payment_orders po SET shopkeeper_id = $1, shopkeeper_amount = COALESCE(po.shopkeeper_amount, po.amount * (1 - COALESCE(po.platform_commission, 0)))
			 WHERE po.status = 'paid' AND po.shopkeeper_id IS NULL
			 AND EXISTS (SELECT 1 FROM files f WHERE f.payment_order_id = po.id AND f.shop_id = $1 AND f.status = 'downloaded')`,
			shopkeeperID)
		_, _ = database.DB.Exec(context.Background(),
			`INSERT INTO shopkeeper_payouts (shopkeeper_id, payment_order_id, amount, status)
			 SELECT $1, po.id, COALESCE(po.shopkeeper_amount, po.amount * (1 - COALESCE(po.platform_commission, 0))), 'pending'
			 FROM payment_orders po
			 WHERE po.status = 'paid' AND po.shopkeeper_id = $1
			 AND EXISTS (SELECT 1 FROM files f WHERE f.payment_order_id = po.id AND f.shop_id = $1 AND f.status = 'downloaded')
			 AND NOT EXISTS (SELECT 1 FROM shopkeeper_payouts sp WHERE sp.payment_order_id = po.id AND sp.shopkeeper_id = $1)`,
			shopkeeperID)
	}

	offset := (page - 1) * pageSize
	baseQuery := `
		SELECT sp.id, sp.shopkeeper_id, COALESCE(NULLIF(TRIM(u.shop_name), ''), NULLIF(TRIM(u.full_name), ''), '') as shopkeeper_name, sp.payment_order_id,
		       po.order_id, sp.amount, sp.status, sp.payout_method, sp.payout_reference,
		       sp.created_at, sp.paid_at, sp.failed_at, sp.failure_reason
		FROM shopkeeper_payouts sp
		JOIN users u ON sp.shopkeeper_id = u.id
		JOIN payment_orders po ON sp.payment_order_id = po.id
	`
	// Build WHERE and args for list/count/summary (activity date = COALESCE(paid_at, created_at))
	var whereParts []string
	var args []interface{}
	argNum := 1
	if status != "" {
		whereParts = append(whereParts, fmt.Sprintf("sp.status = $%d", argNum))
		args = append(args, status)
		argNum++
	}
	if shopkeeperIDStr != "" {
		shopkeeperID, _ := strconv.Atoi(shopkeeperIDStr)
		whereParts = append(whereParts, fmt.Sprintf("sp.shopkeeper_id = $%d", argNum))
		args = append(args, shopkeeperID)
		argNum++
	}
	if fromDate != nil && toDate != nil {
		whereParts = append(whereParts, fmt.Sprintf("(COALESCE(sp.paid_at, sp.created_at) >= $%d AND COALESCE(sp.paid_at, sp.created_at) < $%d + INTERVAL '1 day')", argNum, argNum+1))
		args = append(args, *fromDate, *toDate)
		argNum += 2
	}
	whereClause := ""
	if len(whereParts) > 0 {
		whereClause = " WHERE " + whereParts[0]
		for i := 1; i < len(whereParts); i++ {
			whereClause += " AND " + whereParts[i]
		}
	}

	// List query
	listArgs := make([]interface{}, len(args))
	copy(listArgs, args)
	listArgs = append(listArgs, pageSize, offset)
	listQuery := baseQuery + whereClause + fmt.Sprintf(" ORDER BY sp.created_at DESC LIMIT $%d OFFSET $%d", argNum, argNum+1)

	rows, err := database.DB.Query(context.Background(), listQuery, listArgs...)
	if err != nil {
		log.Printf("GetPayouts: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var payouts []PayoutDetail
	for rows.Next() {
		var payout PayoutDetail
		err := rows.Scan(
			&payout.ID, &payout.ShopkeeperID, &payout.ShopkeeperName, &payout.PaymentOrderID,
			&payout.OrderID, &payout.Amount, &payout.Status, &payout.PayoutMethod,
			&payout.PayoutReference, &payout.CreatedAt, &payout.PaidAt,
			&payout.FailedAt, &payout.FailureReason,
		)
		if err != nil {
			log.Printf("GetPayouts: scan: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}
		payouts = append(payouts, payout)
	}

	// Total count with same filter
	countQuery := "SELECT COUNT(*) FROM shopkeeper_payouts sp" + whereClause
	var total int
	err = database.DB.QueryRow(context.Background(), countQuery, args...).Scan(&total)
	if err != nil {
		log.Printf("GetPayouts: count: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	totalPages := (total + pageSize - 1) / pageSize
	response := PayoutListResponse{
		Payouts:    payouts,
		Total:      total,
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
	}

	// Summary for current filter: same date + shopkeeper filter, then pending and paid totals
	var pendingCount int
	var pendingAmount float64
	var paidCount int
	var paidAmount float64
	sumWhereParts := []string{}
	sumArgs := []interface{}{}
	si := 1
	if shopkeeperIDStr != "" {
		shopkeeperID, _ := strconv.Atoi(shopkeeperIDStr)
		sumWhereParts = append(sumWhereParts, fmt.Sprintf("sp.shopkeeper_id = $%d", si))
		sumArgs = append(sumArgs, shopkeeperID)
		si++
	}
	if fromDate != nil && toDate != nil {
		sumWhereParts = append(sumWhereParts, fmt.Sprintf("(COALESCE(sp.paid_at, sp.created_at) >= $%d AND COALESCE(sp.paid_at, sp.created_at) < $%d + INTERVAL '1 day')", si, si+1))
		sumArgs = append(sumArgs, *fromDate, *toDate)
		si += 2
	}
	{
		sumWhere := ""
		if len(sumWhereParts) > 0 {
			sumWhere = " WHERE " + strings.Join(sumWhereParts, " AND ") + " AND "
		} else {
			sumWhere = " WHERE "
		}
		_ = database.DB.QueryRow(context.Background(),
			"SELECT COUNT(*), COALESCE(SUM(sp.amount), 0) FROM shopkeeper_payouts sp"+sumWhere+"sp.status = 'pending'",
			sumArgs...).Scan(&pendingCount, &pendingAmount)
		_ = database.DB.QueryRow(context.Background(),
			"SELECT COUNT(*), COALESCE(SUM(sp.amount), 0) FROM shopkeeper_payouts sp"+sumWhere+"sp.status = 'paid'",
			sumArgs...).Scan(&paidCount, &paidAmount)
	}
	response.Summary = &PayoutSummary{
		TotalPendingCount:  pendingCount,
		TotalPendingAmount: pendingAmount,
		TotalPaidCount:     paidCount,
		TotalPaidAmount:    paidAmount,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

// UpdatePayoutStatus updates the status of a payout
func UpdatePayoutStatus(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req struct {
		PayoutID        int     `json:"payout_id"`
		Status          string  `json:"status"`
		PayoutMethod    *string `json:"payout_method,omitempty"`
		PayoutReference *string `json:"payout_reference,omitempty"`
		FailureReason   *string `json:"failure_reason,omitempty"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.Status != "pending" && req.Status != "paid" && req.Status != "failed" {
		http.Error(w, "Invalid status. Must be 'pending', 'paid', or 'failed'", http.StatusBadRequest)
		return
	}

	var paidAt *time.Time
	var failedAt *time.Time
	if req.Status == "paid" {
		now := time.Now()
		paidAt = &now
	}
	if req.Status == "failed" {
		now := time.Now()
		failedAt = &now
	}

	// Only set failed_at/failure_reason when marking as failed; when marking as paid leave them (audit trail)
	_, err := database.DB.Exec(context.Background(),
		`UPDATE shopkeeper_payouts 
		 SET status = $1, payout_method = $2, payout_reference = $3, paid_at = $4,
		     failed_at = CASE WHEN $1 = 'failed' THEN $5 ELSE failed_at END,
		     failure_reason = CASE WHEN $1 = 'failed' THEN $6 ELSE failure_reason END
		 WHERE id = $7`,
		req.Status, req.PayoutMethod, req.PayoutReference, paidAt, failedAt, req.FailureReason, req.PayoutID)

	if err != nil {
		log.Printf("UpdatePayoutStatus: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	LogAdmin(claims.UserID, "update_payout", fmt.Sprintf("%d", req.PayoutID), req.Status)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Payout updated successfully"})
}

// BulkUpdatePayoutsRequest is the body for bulk payout update
type BulkUpdatePayoutsRequest struct {
	PayoutIDs        []int   `json:"payout_ids"`
	Status           string  `json:"status"`
	PayoutMethod     *string `json:"payout_method,omitempty"`
	PayoutReference  *string `json:"payout_reference,omitempty"`
}

// BulkUpdatePayouts marks multiple payouts as paid/failed with the same method/reference
func BulkUpdatePayouts(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req BulkUpdatePayoutsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if len(req.PayoutIDs) == 0 {
		http.Error(w, "payout_ids required and must not be empty", http.StatusBadRequest)
		return
	}
	if req.Status != "paid" && req.Status != "failed" {
		http.Error(w, "status must be 'paid' or 'failed'", http.StatusBadRequest)
		return
	}
	if req.Status == "paid" && (req.PayoutMethod == nil || *req.PayoutMethod == "" || req.PayoutReference == nil || *req.PayoutReference == "") {
		http.Error(w, "payout_method and payout_reference required when marking as paid", http.StatusBadRequest)
		return
	}

	var paidAt *time.Time
	var failedAt *time.Time
	if req.Status == "paid" {
		now := time.Now()
		paidAt = &now
	}
	if req.Status == "failed" {
		now := time.Now()
		failedAt = &now
	}

	// Update all by ID (idempotent; only update rows that exist)
	for _, id := range req.PayoutIDs {
		_, _ = database.DB.Exec(context.Background(),
			`UPDATE shopkeeper_payouts 
			 SET status = $1, payout_method = $2, payout_reference = $3, paid_at = $4,
			     failed_at = CASE WHEN $1 = 'failed' THEN $5 ELSE failed_at END
			 WHERE id = $6`,
			req.Status, req.PayoutMethod, req.PayoutReference, paidAt, failedAt, id)
	}

	LogAdmin(claims.UserID, "bulk_update_payouts", fmt.Sprintf("%d ids: %v", len(req.PayoutIDs), req.PayoutIDs), req.Status)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"message": "Payouts updated successfully", "updated": len(req.PayoutIDs)})
}

// ExportPayouts returns CSV of payouts with same filters as GET /admin/payouts
func ExportPayouts(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	shopkeeperIDStr := r.URL.Query().Get("shopkeeper_id")
	fromDate, toDate := payoutDateRange(r)

	baseQuery := `
		SELECT sp.id, sp.shopkeeper_id, COALESCE(NULLIF(TRIM(u.shop_name), ''), NULLIF(TRIM(u.full_name), ''), '') as shopkeeper_name, sp.payment_order_id,
		       po.order_id, sp.amount, sp.status, sp.payout_method, sp.payout_reference,
		       sp.created_at, sp.paid_at
		FROM shopkeeper_payouts sp
		JOIN users u ON sp.shopkeeper_id = u.id
		JOIN payment_orders po ON sp.payment_order_id = po.id
	`
	var whereParts []string
	var args []interface{}
	argNum := 1
	if status != "" {
		whereParts = append(whereParts, fmt.Sprintf("sp.status = $%d", argNum))
		args = append(args, status)
		argNum++
	}
	if shopkeeperIDStr != "" {
		shopkeeperID, _ := strconv.Atoi(shopkeeperIDStr)
		whereParts = append(whereParts, fmt.Sprintf("sp.shopkeeper_id = $%d", argNum))
		args = append(args, shopkeeperID)
		argNum++
	}
	if fromDate != nil && toDate != nil {
		whereParts = append(whereParts, fmt.Sprintf("(COALESCE(sp.paid_at, sp.created_at) >= $%d AND COALESCE(sp.paid_at, sp.created_at) < $%d + INTERVAL '1 day')", argNum, argNum+1))
		args = append(args, *fromDate, *toDate)
	}
	whereClause := ""
	if len(whereParts) > 0 {
		whereClause = " WHERE " + strings.Join(whereParts, " AND ")
	}

	rows, err := database.DB.Query(context.Background(), baseQuery+whereClause+" ORDER BY sp.created_at DESC", args...)
	if err != nil {
		log.Printf("ExportPayouts: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	w.Header().Set("Content-Type", "text/csv")
	w.Header().Set("Content-Disposition", "attachment; filename=payouts.csv")
	cw := csv.NewWriter(w)
	_ = cw.Write([]string{"payout_id", "shopkeeper_id", "shopkeeper_name", "order_id", "amount", "status", "created_at", "paid_at", "payout_method", "payout_reference"})

	for rows.Next() {
		var id, shopkeeperID, paymentOrderID int
		var shopkeeperName, orderID string
		var amount float64
		var statusStr string
		var payoutMethod, payoutReference sql.NullString
		var createdAt time.Time
		var paidAt sql.NullTime
		err := rows.Scan(&id, &shopkeeperID, &shopkeeperName, &paymentOrderID, &orderID, &amount, &statusStr, &payoutMethod, &payoutReference, &createdAt, &paidAt)
		if err != nil {
			log.Printf("ExportPayouts: scan: %v", err)
			continue
		}
		paidAtStr := ""
		if paidAt.Valid {
			paidAtStr = paidAt.Time.Format("2006-01-02 15:04:05")
		}
		methodStr := ""
		if payoutMethod.Valid {
			methodStr = payoutMethod.String
		}
		refStr := ""
		if payoutReference.Valid {
			refStr = payoutReference.String
		}
		_ = cw.Write([]string{
			strconv.Itoa(id),
			strconv.Itoa(shopkeeperID),
			shopkeeperName,
			orderID,
			fmt.Sprintf("%.2f", amount),
			statusStr,
			createdAt.Format("2006-01-02 15:04:05"),
			paidAtStr,
			methodStr,
			refStr,
		})
	}
	cw.Flush()
}

// DeleteAccount deletes a user account and all associated data
func DeleteAccount(w http.ResponseWriter, r *http.Request) {
	var req DeleteAccountRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Prevent admin from deleting themselves
	if claims.UserID == req.UserID {
		http.Error(w, "Cannot delete your own account", http.StatusBadRequest)
		return
	}

	// Check if user exists and get role
	var role string
	err := database.DB.QueryRow(context.Background(),
		"SELECT role FROM users WHERE id = $1", req.UserID).Scan(&role)
	if err == sql.ErrNoRows {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}
	if err != nil {
		log.Printf("GetUserDetails: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Prevent deleting admin accounts
	if role == "admin" {
		http.Error(w, "Cannot delete admin accounts", http.StatusForbidden)
		return
	}

	// Start transaction for atomic deletion
	tx, err := database.DB.Begin(context.Background())
	if err != nil {
		log.Printf("DeleteAccount: transaction: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(context.Background())

	// Get all file paths before deletion
	var filePaths []string
	rows, err := tx.Query(context.Background(),
		"SELECT file_path FROM files WHERE user_id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: get files: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	for rows.Next() {
		var filePath string
		if err := rows.Scan(&filePath); err == nil {
			filePaths = append(filePaths, filePath)
		}
	}
	rows.Close()

	// Delete password reset tokens
	_, err = tx.Exec(context.Background(),
		"DELETE FROM password_reset_tokens WHERE user_id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: delete reset tokens: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Delete shopkeeper payouts (cascade should handle this, but explicit for clarity)
	_, err = tx.Exec(context.Background(),
		"DELETE FROM shopkeeper_payouts WHERE shopkeeper_id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: delete payouts: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Delete wallet transactions (must happen before deleting payment_orders, since they reference payment_orders.id)
	_, err = tx.Exec(context.Background(),
		"DELETE FROM wallet_transactions WHERE user_id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: delete wallet_transactions: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Delete wallet topup orders for this user
	_, err = tx.Exec(context.Background(),
		"DELETE FROM wallet_topup_orders WHERE user_id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: delete wallet_topup_orders: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Update payment orders to set shopkeeper_id to NULL if this user was a shopkeeper
	_, err = tx.Exec(context.Background(),
		"UPDATE payment_orders SET shopkeeper_id = NULL WHERE shopkeeper_id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: update payment orders: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Clear shop_id on files where this user was the shopkeeper (queue prints)
	_, err = tx.Exec(context.Background(),
		"UPDATE files SET shop_id = NULL WHERE shop_id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: clear files.shop_id: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Delete files (this will cascade to payment_orders.file_id)
	_, err = tx.Exec(context.Background(),
		"DELETE FROM files WHERE user_id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: delete files: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Delete payment orders
	_, err = tx.Exec(context.Background(),
		"DELETE FROM payment_orders WHERE user_id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: delete payment orders: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Remove referral data that references this user (so delete works for customers created via referral).
	// If referral tables don't exist (older DB), skip without failing (42P01 = undefined_table).
	execReferralCleanup := func(query string, args ...interface{}) bool {
		_, execErr := tx.Exec(context.Background(), query, args...)
		if execErr != nil {
			var pgErr *pgconn.PgError
			if errors.As(execErr, &pgErr) && pgErr.Code == "42P01" {
				log.Printf("DeleteAccount: referral table not present, skipping: %v", execErr)
				return true
			}
			log.Printf("DeleteAccount: referral cleanup: %v", execErr)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return false
		}
		return true
	}
	if !execReferralCleanup("DELETE FROM referral_invite_log WHERE referrer_id = $1", req.UserID) {
		return
	}
	// Only delete referrals where deleted user was referrer. Keep rows where they were referee (status=credited, referee_email) so same email cannot get referee bonus again after re-register.
	if !execReferralCleanup("DELETE FROM referrals WHERE referrer_id = $1", req.UserID) {
		return
	}

	// Delete user
	_, err = tx.Exec(context.Background(),
		"DELETE FROM users WHERE id = $1", req.UserID)
	if err != nil {
		log.Printf("DeleteAccount: delete user: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Commit transaction
	if err = tx.Commit(context.Background()); err != nil {
		log.Printf("DeleteAccount: commit: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	LogAdmin(claims.UserID, "delete_user", fmt.Sprintf("%d", req.UserID), "")

	// Delete physical files
	uploadsDir := os.Getenv("UPLOADS_DIR")
	if uploadsDir == "" {
		uploadsDir = "backend/uploads"
		// Try current directory if backend/uploads doesn't exist
		if _, err := os.Stat(uploadsDir); os.IsNotExist(err) {
			uploadsDir = "uploads"
		}
	}
	for _, filePath := range filePaths {
		// Extract just the filename from the stored path
		filename := filepath.Base(filePath)
		fullPath := filepath.Join(uploadsDir, filename)
		// Try to remove, but don't fail if file doesn't exist
		os.Remove(fullPath)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": fmt.Sprintf("Account %d deleted successfully", req.UserID),
	})
}

// UpdateAppDownloads updates app download links and "coming soon" flags. Admin only.
func UpdateAppDownloads(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req struct {
		WindowsShopkeeperURL string `json:"windows_shopkeeper_url"`
		AndroidCustomerURL   string `json:"android_customer_url"`
		IosCustomerURL       string `json:"ios_customer_url"`
		WindowsComingSoon    *bool  `json:"windows_coming_soon"`
		AndroidComingSoon    *bool  `json:"android_coming_soon"`
		IosComingSoon        *bool  `json:"ios_coming_soon"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	windowsComingSoon := true
	if req.WindowsComingSoon != nil {
		windowsComingSoon = *req.WindowsComingSoon
	}
	androidComingSoon := true
	if req.AndroidComingSoon != nil {
		androidComingSoon = *req.AndroidComingSoon
	}
	iosComingSoon := true
	if req.IosComingSoon != nil {
		iosComingSoon = *req.IosComingSoon
	}

	_, err := database.DB.Exec(context.Background(),
		`INSERT INTO app_download_links (id, windows_shopkeeper_url, android_customer_url, ios_customer_url, windows_coming_soon, android_coming_soon, ios_coming_soon, updated_at)
		 VALUES (1, $1, $2, $3, $4, $5, $6, NOW())
		 ON CONFLICT (id) DO UPDATE SET
		   windows_shopkeeper_url = EXCLUDED.windows_shopkeeper_url,
		   android_customer_url = EXCLUDED.android_customer_url,
		   ios_customer_url = EXCLUDED.ios_customer_url,
		   windows_coming_soon = EXCLUDED.windows_coming_soon,
		   android_coming_soon = EXCLUDED.android_coming_soon,
		   ios_coming_soon = EXCLUDED.ios_coming_soon,
		   updated_at = NOW()`,
		req.WindowsShopkeeperURL, req.AndroidCustomerURL, req.IosCustomerURL, windowsComingSoon, androidComingSoon, iosComingSoon)
	if err != nil {
		log.Printf("UpdateAppDownloads: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	LogAdmin(claims.UserID, "update_app_downloads", "", "")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "App download links updated successfully"})
}

// SendNotificationRequest is the body for POST /admin/notifications/send
type SendNotificationRequest struct {
	Title string            `json:"title"`
	Body  string            `json:"body"`
	Data  map[string]string `json:"data,omitempty"`
}

// SendNotificationToAllCustomers sends a push notification to every customer who has registered an FCM token (Android/iOS app users).
func SendNotificationToAllCustomers(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok || claims.Role != "admin" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var req SendNotificationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	req.Body = strings.TrimSpace(req.Body)
	if req.Title == "" {
		http.Error(w, "Title is required", http.StatusBadRequest)
		return
	}
	if req.Body == "" {
		req.Body = req.Title
	}
	if req.Data == nil {
		req.Data = make(map[string]string)
	}
	req.Data["type"] = "admin_broadcast"

	ctx := r.Context()
	userIDs, err := notifications.GetCustomerUserIDsWithTokens(ctx)
	if err != nil {
		log.Printf("SendNotificationToAllCustomers: %v", err)
		http.Error(w, "Failed to get recipients", http.StatusInternalServerError)
		return
	}

	notifications.SendToUsers(userIDs, req.Title, req.Body, req.Data)
	LogAdmin(claims.UserID, "send_notification_all", req.Title, "")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"message":    "Notification sent",
		"recipients": len(userIDs),
	})
}
