package admin

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"backend/internal/auth"
	"backend/internal/database"
)

// TwoFAStatus returns whether email 2FA is enabled for the current admin. Admin only.
func TwoFAStatus(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok || claims.Role != "admin" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var enabled bool
	_ = database.DB.QueryRow(context.Background(),
		"SELECT COALESCE(email_2fa_enabled, false) FROM users WHERE id = $1", claims.UserID).Scan(&enabled)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"enabled": enabled})
}

// TwoFAEnable enables email 2FA for the admin. Admin must have an email set. Admin only.
func TwoFAEnable(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok || claims.Role != "admin" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var email string
	err := database.DB.QueryRow(context.Background(),
		"SELECT COALESCE(TRIM(email), '') FROM users WHERE id = $1", claims.UserID).Scan(&email)
	if err != nil || email == "" {
		http.Error(w, "Add an email to your account first (profile or create_admin) to use email 2FA", http.StatusBadRequest)
		return
	}

	_, err = database.DB.Exec(context.Background(),
		"UPDATE users SET email_2fa_enabled = true WHERE id = $1", claims.UserID)
	if err != nil {
		http.Error(w, "Failed to enable 2FA", http.StatusInternalServerError)
		return
	}

	LogAdmin(claims.UserID, "email_2fa_enabled", "", "")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Email 2FA enabled. A code will be sent to your email when you sign in."})
}

// TwoFADisableRequest is the body for POST /admin/2fa/disable
type TwoFADisableRequest struct {
	Password string `json:"password"`
}

// TwoFADisable disables email 2FA after password confirmation. Admin only.
func TwoFADisable(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok || claims.Role != "admin" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var req TwoFADisableRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if strings.TrimSpace(req.Password) == "" {
		http.Error(w, "Password is required to disable 2FA", http.StatusBadRequest)
		return
	}

	var passwordHash string
	err := database.DB.QueryRow(context.Background(),
		"SELECT password_hash FROM users WHERE id = $1", claims.UserID).Scan(&passwordHash)
	if err != nil {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}
	if !auth.CheckPasswordHash(req.Password, passwordHash) {
		http.Error(w, "Invalid password", http.StatusUnauthorized)
		return
	}

	_, err = database.DB.Exec(context.Background(),
		`UPDATE users SET email_2fa_enabled = false WHERE id = $1`,
		claims.UserID)
	if err != nil {
		http.Error(w, "Failed to disable 2FA", http.StatusInternalServerError)
		return
	}

	// Clear any pending login 2FA code for this user
	_, _ = database.DB.Exec(context.Background(), "DELETE FROM login_2fa_otps WHERE user_id = $1", claims.UserID)

	LogAdmin(claims.UserID, "email_2fa_disabled", "", "")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "2FA disabled successfully"})
}
