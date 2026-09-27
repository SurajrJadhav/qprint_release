package handlers

import (
	"backend/internal/auth"
	"backend/internal/database"
	"backend/internal/email"
	"backend/internal/models"
	"backend/internal/notifications"
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var referralInviteEmailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)

// Referral bonus amounts (configurable via env)
func referralBonusReferrer() float64 {
	s := os.Getenv("REFERRAL_BONUS_REFERRER")
	if s == "" {
		return 50.0
	}
	f, _ := strconv.ParseFloat(s, 64)
	if f < 0 {
		return 0
	}
	if f > 10000 {
		return 10000
	}
	return f
}

func referralBonusReferee() float64 {
	s := os.Getenv("REFERRAL_BONUS_REFEREE")
	if s == "" {
		return 25.0
	}
	f, _ := strconv.ParseFloat(s, 64)
	if f < 0 {
		return 0
	}
	if f > 10000 {
		return 10000
	}
	return f
}

// GetReferralSummary returns total referred, total credited, total earnings, pending (signed_up but not credited).
func GetReferralSummary(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	if claims.Role != "customer" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var totalReferred, totalCredited int
	var totalEarnings float64
	_ = database.DB.QueryRow(context.Background(),
		`SELECT COUNT(*), COALESCE(SUM(CASE WHEN status = 'credited' THEN 1 ELSE 0 END), 0),
		 COALESCE(SUM(CASE WHEN status = 'credited' THEN amount_credited_referrer ELSE 0 END), 0)
		 FROM referrals WHERE referrer_id = $1`,
		claims.UserID).Scan(&totalReferred, &totalCredited, &totalEarnings)

	pending := totalReferred - totalCredited
	if pending < 0 {
		pending = 0
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(models.ReferralSummary{
		TotalReferred: totalReferred,
		TotalCredited: totalCredited,
		TotalEarnings: totalEarnings,
		PendingCount:  pending,
	})
}

// GetReferralHistory returns list of referrals (masked referee, status, amount, dates).
func GetReferralHistory(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	if claims.Role != "customer" {
		http.Error(w, "Forbidden", http.StatusForbidden)
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

	rows, err := database.DB.Query(context.Background(),
		`SELECT id, status, amount_credited_referrer, credited_at, created_at
		 FROM referrals WHERE referrer_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
		claims.UserID, limit, offset)
	if err != nil {
		log.Printf("GetReferralHistory: %v", err)
		http.Error(w, "An error occurred.", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var list []models.ReferralHistoryItem
	for rows.Next() {
		var item models.ReferralHistoryItem
		var amount float64
		var creditedAt *time.Time
		if err := rows.Scan(&item.ID, &item.Status, &amount, &creditedAt, &item.CreatedAt); err != nil {
			continue
		}
		item.Amount = amount
		item.CreditedAt = creditedAt
		list = append(list, item)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"referrals": list})
}

// ReferralInviteRequest is the body for POST /referral/invite (invite by email only; SMS skipped).
type ReferralInviteRequest struct {
	Email string `json:"email"`
}

// ReferralInvite sends an invite email with the referrer's link. Customer only. Rate limited per referrer per 24h.
func ReferralInvite(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	if claims.Role != "customer" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var req ReferralInviteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	to := strings.TrimSpace(strings.ToLower(req.Email))
	if to == "" || !referralInviteEmailRegex.MatchString(to) {
		http.Error(w, "Invalid email address", http.StatusBadRequest)
		return
	}

	maxPerDay := 20
	if s := os.Getenv("REFERRAL_INVITE_MAX_PER_DAY"); s != "" {
		if n, _ := strconv.Atoi(s); n > 0 && n <= 100 {
			maxPerDay = n
		}
	}

	var count int
	err := database.DB.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM referral_invite_log WHERE referrer_id = $1 AND created_at > NOW() - INTERVAL '24 hours'`,
		claims.UserID).Scan(&count)
	if err != nil {
		log.Printf("ReferralInvite: count: %v", err)
		http.Error(w, "An error occurred.", http.StatusInternalServerError)
		return
	}
	if count >= maxPerDay {
		http.Error(w, "Daily invite limit reached. Try again tomorrow.", http.StatusTooManyRequests)
		return
	}

	var referralCode *string
	var fullName string
	_ = database.DB.QueryRow(context.Background(),
		"SELECT referral_code, COALESCE(full_name, '') FROM users WHERE id = $1", claims.UserID).Scan(&referralCode, &fullName)
	if referralCode == nil || *referralCode == "" {
		http.Error(w, "Referral code not available.", http.StatusBadRequest)
		return
	}
	baseURL := os.Getenv("REFERRAL_BASE_URL")
	if baseURL == "" {
		baseURL = "https://qprint.co.in"
	}
	referralLink := strings.TrimSuffix(baseURL, "/") + "/r/" + *referralCode

	if err := email.SendReferralInviteEmail(to, fullName, referralLink); err != nil {
		log.Printf("ReferralInvite: send email: %v", err)
		http.Error(w, "Failed to send invite email. Please try again later.", http.StatusInternalServerError)
		return
	}
	_, _ = database.DB.Exec(context.Background(),
		"INSERT INTO referral_invite_log (referrer_id, invited_email) VALUES ($1, $2)", claims.UserID, to)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"ok": true, "message": "Invite sent."})
}

// TryCreditReferral is called after a qualifying action (first top-up or first print payment).
// refereeUserID is the user who just completed the action. Idempotent: if already credited, no-op.
func TryCreditReferral(refereeUserID int) {
	tx, err := database.DB.Begin(context.Background())
	if err != nil {
		log.Printf("TryCreditReferral: begin: %v", err)
		return
	}
	defer tx.Rollback(context.Background())

	var referrerID, referralID int
	var codeUsed string
	err = tx.QueryRow(context.Background(),
		`SELECT id, referrer_id, referral_code_used FROM referrals WHERE referee_id = $1 AND status = 'signed_up' LIMIT 1`,
		refereeUserID).Scan(&referralID, &referrerID, &codeUsed)
	if err != nil {
		return // no pending referral
	}

	if referrerID == 0 {
		return
	}
	if referrerID == refereeUserID {
		return // self-referral
	}

	// Time window: referee must have qualified within N days of signup (optional)
	if daysEnv := os.Getenv("REFERRAL_QUALIFY_DAYS"); daysEnv != "" {
		if days, _ := strconv.Atoi(daysEnv); days > 0 {
			var refereeCreatedAt time.Time
			if tx.QueryRow(context.Background(), "SELECT created_at FROM users WHERE id = $1", refereeUserID).Scan(&refereeCreatedAt) == nil {
				if time.Since(refereeCreatedAt) > time.Duration(days)*24*time.Hour {
					return // outside time window
				}
			}
		}
	}

	// Cap per referrer: max N credited referrals (optional)
	if capEnv := os.Getenv("REFERRAL_CAP_PER_REFERRER"); capEnv != "" {
		if capN, _ := strconv.Atoi(capEnv); capN > 0 {
			var creditedCount int
			if tx.QueryRow(context.Background(), "SELECT COUNT(*) FROM referrals WHERE referrer_id = $1 AND status = 'credited'", referrerID).Scan(&creditedCount) == nil && creditedCount >= capN {
				return
			}
		}
	}

	// Get referee email and phone (normalised)
	var refereeEmail, refereePhone *string
	_ = tx.QueryRow(context.Background(),
		"SELECT TRIM(LOWER(email)), TRIM(phone) FROM users WHERE id = $1", refereeUserID).Scan(&refereeEmail, &refereePhone)

	emailNorm := ""
	if refereeEmail != nil && *refereeEmail != "" {
		emailNorm = *refereeEmail
	}
	phoneNorm := ""
	if refereePhone != nil && *refereePhone != "" {
		phoneNorm = strings.TrimSpace(*refereePhone)
	}

	// One referee bonus per email (and per phone) once in a lifetime. If this email/phone was ever
	// credited as referee in any referral (including after account delete + re-register), do not credit again.
	if emailNorm != "" {
		var alreadyCredited int
		if tx.QueryRow(context.Background(),
			`SELECT 1 FROM referrals WHERE status = 'credited' AND TRIM(LOWER(referee_email)) = $1 LIMIT 1`,
			emailNorm).Scan(&alreadyCredited) == nil {
			return
		}
	}
	if phoneNorm != "" {
		var alreadyCredited int
		if tx.QueryRow(context.Background(),
			`SELECT 1 FROM referrals WHERE status = 'credited' AND referee_phone IS NOT NULL AND TRIM(referee_phone) = $1 LIMIT 1`,
			phoneNorm).Scan(&alreadyCredited) == nil {
			return
		}
	}

	// One credit per (referrer_id, referee_email) and per (referrer_id, referee_phone) ever (referrer side)
	if emailNorm != "" {
		var dup int
		if tx.QueryRow(context.Background(),
			`SELECT 1 FROM referrals WHERE referrer_id = $1 AND status = 'credited' AND TRIM(LOWER(referee_email)) = $2 LIMIT 1`,
			referrerID, emailNorm).Scan(&dup) == nil {
			return
		}
	}
	if phoneNorm != "" {
		var dup int
		if tx.QueryRow(context.Background(),
			`SELECT 1 FROM referrals WHERE referrer_id = $1 AND status = 'credited' AND TRIM(referee_phone) = $2 LIMIT 1`,
			referrerID, phoneNorm).Scan(&dup) == nil {
			return
		}
	}

	bonusRef := referralBonusReferrer()
	bonusReferee := referralBonusReferee()

	// Credit referrer
	var refBalanceBefore, refBalanceAfter float64
	err = tx.QueryRow(context.Background(),
		"SELECT COALESCE(wallet_balance, 0) FROM users WHERE id = $1", referrerID).Scan(&refBalanceBefore)
	if err != nil {
		return
	}
	refBalanceAfter = refBalanceBefore + bonusRef
	_, err = tx.Exec(context.Background(),
		"UPDATE users SET wallet_balance = $1 WHERE id = $2", refBalanceAfter, referrerID)
	if err != nil {
		log.Printf("TryCreditReferral: update referrer balance: %v", err)
		return
	}
	_, err = tx.Exec(context.Background(),
		`INSERT INTO wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, status, description)
		 VALUES ($1, 'referral_bonus', $2, $3, $4, 'completed', 'Referral bonus')`,
		referrerID, bonusRef, refBalanceBefore, refBalanceAfter)
	if err != nil {
		log.Printf("TryCreditReferral: insert referrer tx: %v", err)
		return
	}

	// Optionally credit referee (welcome bonus)
	if bonusReferee > 0 {
		var refeeBalanceBefore, refeeBalanceAfter float64
		_ = tx.QueryRow(context.Background(),
			"SELECT COALESCE(wallet_balance, 0) FROM users WHERE id = $1", refereeUserID).Scan(&refeeBalanceBefore)
		refeeBalanceAfter = refeeBalanceBefore + bonusReferee
		_, _ = tx.Exec(context.Background(),
			"UPDATE users SET wallet_balance = $1 WHERE id = $2", refeeBalanceAfter, refereeUserID)
		_, _ = tx.Exec(context.Background(),
			`INSERT INTO wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, status, description)
			 VALUES ($1, 'referral_welcome', $2, $3, $4, 'completed', 'Welcome bonus')`,
			refereeUserID, bonusReferee, refeeBalanceBefore, refeeBalanceAfter)
	}

	// Update referral row: status=credited, referee_email, referee_phone, amounts, credited_at
	_, err = tx.Exec(context.Background(),
		`UPDATE referrals SET status = 'credited', referee_email = $1, referee_phone = $2,
		 amount_credited_referrer = $3, amount_credited_referee = $4, credited_at = NOW() WHERE id = $5`,
		emailNorm, phoneNorm, bonusRef, bonusReferee, referralID)
	if err != nil {
		log.Printf("TryCreditReferral: update referral: %v", err)
		return
	}

	if err = tx.Commit(context.Background()); err != nil {
		log.Printf("TryCreditReferral: commit: %v", err)
		return
	}
	notifications.SendToUser(referrerID, "Referral credit", "You received "+notifications.FormatAmount(bonusRef)+" for your referral.", map[string]string{"type": "referral_credit"})
	if bonusReferee > 0 {
		notifications.SendToUser(refereeUserID, "Welcome bonus", "You received "+notifications.FormatAmount(bonusReferee)+" welcome bonus from referral.", map[string]string{"type": "referral_welcome"})
	}
}
