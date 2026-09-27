package handlers

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"log"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"backend/internal/auth"
	"backend/internal/database"
	"backend/internal/email"
	"backend/internal/models"
	"backend/internal/utils"
	"backend/internal/notifications"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"
)

const authCookieMaxAge = 86400 // 24 hours

const referralCodeLen = 8
const referralCodeChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no I,O,0,1 to avoid confusion

func generateUniqueReferralCode() string {
	for i := 0; i < 20; i++ {
		b := make([]byte, referralCodeLen)
		if _, err := rand.Read(b); err != nil {
			continue
		}
		for j := 0; j < referralCodeLen; j++ {
			b[j] = referralCodeChars[int(b[j])%len(referralCodeChars)]
		}
		code := string(b)
		var exists int
		if database.DB.QueryRow(context.Background(), "SELECT 1 FROM users WHERE referral_code = $1 LIMIT 1", code).Scan(&exists) != nil {
			return code
		}
	}
	// Fallback: timestamp-based
	return "Q" + hex.EncodeToString([]byte(fmt.Sprintf("%d", time.Now().UnixNano()%10000000)))[:7]
}

// generateUniqueShopCode returns a 6-digit numeric code (100000-999999) unique in users.shop_code.
func generateUniqueShopCode() int {
	for i := 0; i < 50; i++ {
		var b [4]byte
		if _, err := rand.Read(b[:]); err != nil {
			continue
		}
		code := 100000 + (binary.BigEndian.Uint32(b[:]) % 900000)
		c := int(code)
		if c < 100000 {
			c = 100000
		}
		if c > 999999 {
			c = 999999
		}
		var exists int
		if database.DB.QueryRow(context.Background(), "SELECT 1 FROM users WHERE shop_code = $1 LIMIT 1", c).Scan(&exists) != nil {
			return c
		}
	}
	return 100000 + int(time.Now().UnixNano()%900000)
}

// generateInternalUsername returns a unique non-user-facing username (DB requires UNIQUE NOT NULL).
func generateInternalUsername() string {
	for i := 0; i < 20; i++ {
		b := make([]byte, 8)
		if _, err := rand.Read(b); err != nil {
			continue
		}
		u := "u_" + hex.EncodeToString(b)
		var exists int
		if database.DB.QueryRow(context.Background(), "SELECT 1 FROM users WHERE username = $1 LIMIT 1", u).Scan(&exists) != nil {
			return u
		}
	}
	return "u_" + fmt.Sprintf("%x", time.Now().UnixNano())
}

func accountDisplayName(role string, fullName, shopName *string) string {
	if role == "shopkeeper" && shopName != nil && strings.TrimSpace(*shopName) != "" {
		return strings.TrimSpace(*shopName)
	}
	if fullName != nil && strings.TrimSpace(*fullName) != "" {
		return strings.TrimSpace(*fullName)
	}
	return "User"
}

func secureCookie() bool {
	return os.Getenv("ENVIRONMENT") == "production" && os.Getenv("TEST_MODE") != "true"
}

// skipAuthCookie returns true when auth should not use cookies (Bearer-only).
// In production this is true by default; set SKIP_AUTH_COOKIE=false to allow cookie auth.
func skipAuthCookie() bool {
	return auth.BearerOnly()
}

func setAuthCookie(w http.ResponseWriter, token string) {
	if skipAuthCookie() {
		return
	}
	sec := secureCookie()
	sameSite := http.SameSiteNoneMode
	if !sec {
		sameSite = http.SameSiteLaxMode
	}
	http.SetCookie(w, &http.Cookie{
		Name:     auth.CookieName,
		Value:    token,
		Path:     "/",
		MaxAge:   authCookieMaxAge,
		HttpOnly: true,
		SameSite: sameSite,
		Secure:   sec,
	})
}

func clearAuthCookie(w http.ResponseWriter) {
	if skipAuthCookie() {
		return
	}
	sameSite := http.SameSiteNoneMode
	sec := secureCookie()
	if !sec {
		sameSite = http.SameSiteLaxMode
	}
	http.SetCookie(w, &http.Cookie{
		Name:     auth.CookieName,
		Value:    "",
		Path:     "/",
		MaxAge:   0,
		HttpOnly: true,
		SameSite: sameSite,
		Secure:   sec,
	})
}

const signupOTPExpiry = 10 * time.Minute

// RegisterSendOTPRequest is the body for POST /register/send-otp (email only).
type RegisterSendOTPRequest struct {
	Email string `json:"email"`
}

// RegisterSendOTP sends a 6-digit OTP to the given email for sign-up verification.
func RegisterSendOTP(w http.ResponseWriter, r *http.Request) {
	var req RegisterSendOTPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if req.Email == "" || !emailRegex.MatchString(req.Email) {
		http.Error(w, "Valid email is required", http.StatusBadRequest)
		return
	}

	var exists int
	if database.DB.QueryRow(context.Background(), "SELECT 1 FROM users WHERE LOWER(TRIM(email)) = $1 LIMIT 1", req.Email).Scan(&exists) == nil {
		http.Error(w, "This email is already registered.", http.StatusBadRequest)
		return
	}

	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		log.Printf("RegisterSendOTP: rand: %v", err)
		http.Error(w, "Failed to generate code", http.StatusInternalServerError)
		return
	}
	code := fmt.Sprintf("%06d", binary.BigEndian.Uint32(b)%1000000)
	codeHash, err := bcrypt.GenerateFromPassword([]byte(code), 10)
	if err != nil {
		log.Printf("RegisterSendOTP: bcrypt: %v", err)
		http.Error(w, "Failed to generate code", http.StatusInternalServerError)
		return
	}
	expires := time.Now().Add(signupOTPExpiry)
	_, err = database.DB.Exec(context.Background(),
		`INSERT INTO signup_otps (email_lower, code_hash, expires_at) VALUES ($1, $2, $3)
		 ON CONFLICT (email_lower) DO UPDATE SET code_hash = $2, expires_at = $3`,
		req.Email, string(codeHash), expires)
	if err != nil {
		log.Printf("RegisterSendOTP: db: %v", err)
		http.Error(w, "Failed to send code", http.StatusInternalServerError)
		return
	}
	if err := email.SendSignupOTPEmail(req.Email, code); err != nil {
		log.Printf("RegisterSendOTP: send email: %v", err)
		_, _ = database.DB.Exec(context.Background(), "DELETE FROM signup_otps WHERE email_lower = $1", req.Email)
		http.Error(w, "Could not send verification code. Please try again later.", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Verification code sent to your email."})
}

// RegisterVerifyOTPRequest is the body for POST /register/verify-otp (email + code).
type RegisterVerifyOTPRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

// RegisterVerifyOTP exchanges email + 6-digit code for a signup token (short-lived). No account is created yet.
func RegisterVerifyOTP(w http.ResponseWriter, r *http.Request) {
	var req RegisterVerifyOTPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	req.Code = strings.TrimSpace(req.Code)
	if req.Email == "" || req.Code == "" {
		http.Error(w, "Email and code are required", http.StatusBadRequest)
		return
	}
	if len(req.Code) != 6 {
		http.Error(w, "Invalid or expired code", http.StatusBadRequest)
		return
	}

	var codeHash string
	var expiresAt time.Time
	err := database.DB.QueryRow(context.Background(),
		"SELECT code_hash, expires_at FROM signup_otps WHERE email_lower = $1",
		req.Email).Scan(&codeHash, &expiresAt)
	if err != nil {
		http.Error(w, "Invalid or expired code", http.StatusBadRequest)
		return
	}
	if time.Now().After(expiresAt) {
		_, _ = database.DB.Exec(context.Background(), "DELETE FROM signup_otps WHERE email_lower = $1", req.Email)
		http.Error(w, "Invalid or expired code", http.StatusBadRequest)
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(codeHash), []byte(req.Code)) != nil {
		http.Error(w, "Invalid or expired code", http.StatusBadRequest)
		return
	}
	_, _ = database.DB.Exec(context.Background(), "DELETE FROM signup_otps WHERE email_lower = $1", req.Email)
	signupToken, err := auth.GenerateSignupToken(req.Email)
	if err != nil {
		log.Printf("RegisterVerifyOTP: token: %v", err)
		http.Error(w, "Failed to complete verification", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"signup_token": signupToken, "email": req.Email})
}

func Register(w http.ResponseWriter, r *http.Request) {
	var req models.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Register: invalid request body: %v", err)
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	skipOTP := os.Getenv("SKIP_SIGNUP_OTP") == "true"
	if !skipOTP {
		if strings.TrimSpace(req.SignupToken) == "" {
			http.Error(w, "Email verification required. Please request a code and verify your email first.", http.StatusBadRequest)
			return
		}
		verifiedEmail, err := auth.ValidateSignupToken(req.SignupToken)
		if err != nil {
			http.Error(w, "Email verification expired or invalid. Please verify your email again.", http.StatusBadRequest)
			return
		}
		emailNorm := strings.TrimSpace(strings.ToLower(req.Email))
		if emailNorm != verifiedEmail {
			http.Error(w, "Email does not match verified address.", http.StatusBadRequest)
			return
		}
	}

	// Validate required fields
	if strings.TrimSpace(req.FullName) == "" {
		http.Error(w, "Full name is required", http.StatusBadRequest)
		return
	}
	if len(req.FullName) < 2 || len(req.FullName) > 50 {
		http.Error(w, "Full name must be between 2 and 50 characters", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.Email) == "" {
		http.Error(w, "Email is required", http.StatusBadRequest)
		return
	}
	emailRegex := regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)
	if !emailRegex.MatchString(req.Email) {
		http.Error(w, "Invalid email format", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.Phone) == "" {
		http.Error(w, "Phone number is required", http.StatusBadRequest)
		return
	}
	phoneRegex := regexp.MustCompile(`^[0-9]{10}$`)
	cleanPhone := strings.ReplaceAll(req.Phone, " ", "")
	if !phoneRegex.MatchString(cleanPhone) {
		http.Error(w, "Phone number must be 10 digits", http.StatusBadRequest)
		return
	}

	if len(req.Password) < 8 {
		http.Error(w, "Password must be at least 8 characters", http.StatusBadRequest)
		return
	}

	if req.Role != "customer" && req.Role != "shopkeeper" {
		http.Error(w, "Role must be either 'customer' or 'shopkeeper'", http.StatusBadRequest)
		return
	}

	// Validate shopkeeper-specific fields
	if req.Role == "shopkeeper" {
		if strings.TrimSpace(req.ShopName) == "" {
			http.Error(w, "Shop name is required for shopkeeper registration", http.StatusBadRequest)
			return
		}
		if len(req.ShopName) < 2 || len(req.ShopName) > 100 {
			http.Error(w, "Shop name must be between 2 and 100 characters", http.StatusBadRequest)
			return
		}
		if req.Lat == nil || req.Long == nil {
			http.Error(w, "Location (latitude and longitude) is required for shopkeeper registration", http.StatusBadRequest)
			return
		}
		if *req.Lat == 0 && *req.Long == 0 {
			http.Error(w, "Invalid location. Please provide valid latitude and longitude coordinates", http.StatusBadRequest)
			return
		}
		if strings.TrimSpace(req.Address) == "" {
			http.Error(w, "Address is required for shopkeeper registration", http.StatusBadRequest)
			return
		}
	}

	// Check which of email or phone already exist and return a specific message
	var exists int
	var emailTaken, phoneTaken bool
	if database.DB.QueryRow(context.Background(), "SELECT 1 FROM users WHERE email = $1 LIMIT 1", req.Email).Scan(&exists) == nil {
		emailTaken = true
	}
	if database.DB.QueryRow(context.Background(), "SELECT 1 FROM users WHERE phone = $1 LIMIT 1", cleanPhone).Scan(&exists) == nil {
		phoneTaken = true
	}
	if emailTaken || phoneTaken {
		var parts []string
		if emailTaken {
			parts = append(parts, "email")
		}
		if phoneTaken {
			parts = append(parts, "mobile number")
		}
		var msg string
		switch len(parts) {
		case 1:
			msg = "This " + parts[0] + " is already in use."
		case 2:
			msg = "This " + parts[0] + " and " + parts[1] + " are already in use."
		default:
			msg = "This " + strings.Join(parts[:len(parts)-1], ", ") + " and " + parts[len(parts)-1] + " are already in use."
		}
		http.Error(w, msg, http.StatusBadRequest)
		return
	}

	hashedPassword, err := auth.HashPassword(req.Password)
	if err != nil {
		http.Error(w, "Failed to hash password", http.StatusInternalServerError)
		return
	}

	// Resolve referral code (only for customers): referrer must be customer; ignore if invalid
	var referrerID int
	referralCodeNorm := strings.TrimSpace(strings.ToUpper(req.ReferralCode))
	if req.Role == "customer" && referralCodeNorm != "" && len(referralCodeNorm) <= 32 {
		_ = database.DB.QueryRow(context.Background(),
			"SELECT id FROM users WHERE UPPER(TRIM(referral_code)) = $1 AND role = 'customer' LIMIT 1",
			referralCodeNorm).Scan(&referrerID)
	}

	internalUsername := generateInternalUsername()

	var userID int
	if req.Role == "shopkeeper" {
		err = database.DB.QueryRow(context.Background(),
			"INSERT INTO users (username, full_name, email, phone, shop_name, password_hash, role, lat, long, address) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING id",
			internalUsername, req.FullName, req.Email, cleanPhone, req.ShopName, hashedPassword, req.Role, req.Lat, req.Long, req.Address).Scan(&userID)
	} else {
		// Customer: generate unique referral_code; retry on unique violation (race)
		for attempt := 0; attempt < 5; attempt++ {
			newCode := generateUniqueReferralCode()
			err = database.DB.QueryRow(context.Background(),
				"INSERT INTO users (username, full_name, email, phone, password_hash, role, referral_code) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
				internalUsername, req.FullName, req.Email, cleanPhone, hashedPassword, req.Role, newCode).Scan(&userID)
			if err == nil {
				break
			}
			var pgErr *pgconn.PgError
			if errors.As(err, &pgErr) && pgErr.Code == "23505" {
				log.Printf("Register: referral_code collision, retry %d", attempt+1)
				continue
			}
			break
		}
	}

	if err != nil {
		log.Printf("Register: database error: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Create referral row if valid referrer (customer referred by customer).
	// Skip if this email was already credited as referee once (e.g. after delete + re-register) — one per email in lifetime.
	if req.Role == "customer" && referrerID > 0 && referrerID != userID {
		emailNorm := strings.TrimSpace(strings.ToLower(req.Email))
		if emailNorm != "" {
			var alreadyCredited int
			if database.DB.QueryRow(context.Background(),
				`SELECT 1 FROM referrals WHERE status = 'credited' AND TRIM(LOWER(referee_email)) = $1 LIMIT 1`,
				emailNorm).Scan(&alreadyCredited) == nil {
				// Do not create referral row; this email already received referee bonus once
			} else {
				_, _ = database.DB.Exec(context.Background(),
					`INSERT INTO referrals (referrer_id, referee_id, referral_code_used, status) VALUES ($1, $2, $3, 'signed_up')`,
					referrerID, userID, referralCodeNorm)
			}
		} else {
			_, _ = database.DB.Exec(context.Background(),
				`INSERT INTO referrals (referrer_id, referee_id, referral_code_used, status) VALUES ($1, $2, $3, 'signed_up')`,
				referrerID, userID, referralCodeNorm)
		}
	}

	// Notify customers within 10km when a new shop registers
	if req.Role == "shopkeeper" && req.Lat != nil && req.Long != nil {
		notifications.NotifyCustomersNewShopNearby(*req.Lat, *req.Long, strings.TrimSpace(req.ShopName))
	}

	// Return token so client can stay logged in without redirecting to login.
	token, err := auth.GenerateToken(userID, req.Role)
	if err != nil {
		log.Printf("Register: generate token: %v", err)
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]int{"user_id": userID})
		return
	}
	displayName := req.FullName
	if req.Role == "shopkeeper" {
		displayName = req.ShopName
	}
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"user_id":       userID,
		"token":         token,
		"role":          req.Role,
		"display_name":  displayName,
	})
}

// loginIdentifierType classifies the login string as email or phone.
type loginIdentifierType int

const (
	loginTypeInvalid loginIdentifierType = iota
	loginTypeEmail
	loginTypePhone
)

func classifyLoginIdentifier(input string) loginIdentifierType {
	s := strings.TrimSpace(input)
	if s == "" {
		return loginTypeInvalid
	}
	if strings.Contains(s, "@") {
		return loginTypeEmail
	}
	digitsOnly := strings.ReplaceAll(s, " ", "")
	if len(digitsOnly) == 10 {
		for _, c := range digitsOnly {
			if c < '0' || c > '9' {
				return loginTypeInvalid
			}
		}
		return loginTypePhone
	}
	return loginTypeInvalid
}

func Login(w http.ResponseWriter, r *http.Request) {
	var req models.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Login: invalid request body: %v", err)
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	identifier := strings.TrimSpace(req.Login)
	if identifier == "" {
		http.Error(w, "Email or phone is required", http.StatusBadRequest)
		return
	}

	typ := classifyLoginIdentifier(identifier)
	if typ == loginTypeInvalid {
		http.Error(w, "Login with email or 10-digit mobile number only", http.StatusBadRequest)
		return
	}

	var user models.User
	var err error
	switch typ {
	case loginTypeEmail:
		emailLower := strings.ToLower(identifier)
		err = database.DB.QueryRow(context.Background(),
			"SELECT id, password_hash, role, full_name, shop_name FROM users WHERE LOWER(email) = $1",
			emailLower).Scan(&user.ID, &user.PasswordHash, &user.Role, &user.FullName, &user.ShopName)
	case loginTypePhone:
		phoneNorm := strings.ReplaceAll(identifier, " ", "")
		err = database.DB.QueryRow(context.Background(),
			"SELECT id, password_hash, role, full_name, shop_name FROM users WHERE phone = $1",
			phoneNorm).Scan(&user.ID, &user.PasswordHash, &user.Role, &user.FullName, &user.ShopName)
	}

	if err != nil {
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	if !auth.CheckPasswordHash(req.Password, user.PasswordHash) {
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	// If user has email 2FA enabled, send OTP to email and return temp token for 2FA step
	var email2FAEnabled bool
	var userEmail string
	_ = database.DB.QueryRow(context.Background(),
		"SELECT COALESCE(email_2fa_enabled, false), COALESCE(TRIM(email), '') FROM users WHERE id = $1", user.ID).Scan(&email2FAEnabled, &userEmail)
	if email2FAEnabled && userEmail != "" {
		// Generate 6-digit OTP, store hashed, send email
		b := make([]byte, 4)
		if _, err := rand.Read(b); err != nil {
			log.Printf("Login: 2FA rand: %v", err)
			http.Error(w, "Failed to send verification code", http.StatusInternalServerError)
			return
		}
		code := fmt.Sprintf("%06d", binary.BigEndian.Uint32(b)%1000000)
		codeHash, err := bcrypt.GenerateFromPassword([]byte(code), 10)
		if err != nil {
			log.Printf("Login: 2FA bcrypt: %v", err)
			http.Error(w, "Failed to send verification code", http.StatusInternalServerError)
			return
		}
		expires := time.Now().Add(adminOTPExpiry)
		_, err = database.DB.Exec(context.Background(),
			`INSERT INTO login_2fa_otps (user_id, code_hash, expires_at) VALUES ($1, $2, $3)
			 ON CONFLICT (user_id) DO UPDATE SET code_hash = $2, expires_at = $3`,
			user.ID, string(codeHash), expires)
		if err != nil {
			log.Printf("Login: 2FA db: %v", err)
			http.Error(w, "Failed to send verification code", http.StatusInternalServerError)
			return
		}
		if err := email.SendLoginOTPEmail(userEmail, code); err != nil {
			log.Printf("Login: 2FA send email: %v", err)
		}
		tempToken, err := auth.Generate2FAPendingToken(user.ID)
		if err != nil {
			http.Error(w, "Failed to generate token", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"requires_2fa": true,
			"temp_token":   tempToken,
			"display_name": accountDisplayName(user.Role, user.FullName, user.ShopName),
		})
		return
	}

	token, err := auth.GenerateToken(user.ID, user.Role)
	if err != nil {
		http.Error(w, "Failed to generate token", http.StatusInternalServerError)
		return
	}

	setAuthCookie(w, token)
	json.NewEncoder(w).Encode(models.LoginResponse{
		Token:       token,
		Role:        user.Role,
		DisplayName: accountDisplayName(user.Role, user.FullName, user.ShopName),
	})
}

// Verify2FARequest is the body for POST /login/verify-2fa
type Verify2FARequest struct {
	TempToken string `json:"temp_token"`
	Code      string `json:"code"`
}

// Verify2FA exchanges a temp token + email OTP code for a real JWT. Used after password login when user has email 2FA enabled.
func Verify2FA(w http.ResponseWriter, r *http.Request) {
	var req Verify2FARequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	req.Code = strings.TrimSpace(req.Code)
	if req.TempToken == "" || req.Code == "" {
		http.Error(w, "temp_token and code are required", http.StatusBadRequest)
		return
	}
	if len(req.Code) != 6 {
		http.Error(w, "Invalid verification code", http.StatusUnauthorized)
		return
	}

	userID, err := auth.Validate2FAPendingToken(req.TempToken)
	if err != nil {
		http.Error(w, "Invalid or expired login step. Please sign in again.", http.StatusUnauthorized)
		return
	}

	var codeHash string
	var expiresAt time.Time
	err = database.DB.QueryRow(context.Background(),
		"SELECT code_hash, expires_at FROM login_2fa_otps WHERE user_id = $1", userID).Scan(&codeHash, &expiresAt)
	if err != nil {
		http.Error(w, "Invalid or expired code. Please sign in again.", http.StatusUnauthorized)
		return
	}
	if time.Now().After(expiresAt) {
		_, _ = database.DB.Exec(context.Background(), "DELETE FROM login_2fa_otps WHERE user_id = $1", userID)
		http.Error(w, "Code expired. Please sign in again.", http.StatusUnauthorized)
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(codeHash), []byte(req.Code)) != nil {
		http.Error(w, "Invalid verification code", http.StatusUnauthorized)
		return
	}

	_, _ = database.DB.Exec(context.Background(), "DELETE FROM login_2fa_otps WHERE user_id = $1", userID)

	var role string
	var fullName, shopName *string
	err = database.DB.QueryRow(context.Background(),
		"SELECT role, full_name, shop_name FROM users WHERE id = $1 AND COALESCE(email_2fa_enabled, false) = true",
		userID).Scan(&role, &fullName, &shopName)
	if err != nil {
		http.Error(w, "Invalid or expired login step. Please sign in again.", http.StatusUnauthorized)
		return
	}

	token, err := auth.GenerateToken(userID, role)
	if err != nil {
		http.Error(w, "Failed to generate token", http.StatusInternalServerError)
		return
	}

	setAuthCookie(w, token)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(models.LoginResponse{
		Token:       token,
		Role:        role,
		DisplayName: accountDisplayName(role, fullName, shopName),
	})
}

const loginOTPExpiry = 10 * time.Minute
const loginOTPMaxAttempts = 3

// LoginRequestOTPRequest is the body for POST /login/request-otp (email only).
type LoginRequestOTPRequest struct {
	Login string `json:"login"`
}

// LoginRequestOTP sends a 6-digit OTP to the given email if a user exists. OTP login is email-only.
func LoginRequestOTP(w http.ResponseWriter, r *http.Request) {
	var req LoginRequestOTPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	identifier := strings.TrimSpace(req.Login)
	if identifier == "" {
		http.Error(w, "Email is required", http.StatusBadRequest)
		return
	}

	typ := classifyLoginIdentifier(identifier)
	if typ != loginTypeEmail {
		http.Error(w, "OTP login is available for email only. Please enter your email.", http.StatusBadRequest)
		return
	}

	contactValue := strings.ToLower(identifier)
	// Send OTP whether or not the account exists (no enumeration; unknown email → verify returns needs_signup).

	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		log.Printf("LoginRequestOTP: rand: %v", err)
		http.Error(w, "Failed to send code", http.StatusInternalServerError)
		return
	}
	code := fmt.Sprintf("%06d", binary.BigEndian.Uint32(b)%1000000)
	codeHash, err := bcrypt.GenerateFromPassword([]byte(code), 10)
	if err != nil {
		log.Printf("LoginRequestOTP: bcrypt: %v", err)
		http.Error(w, "Failed to send code", http.StatusInternalServerError)
		return
	}
	expires := time.Now().Add(loginOTPExpiry)
	_, err = database.DB.Exec(context.Background(),
		`INSERT INTO login_otps (contact_type, contact_value, code_hash, expires_at, attempts) VALUES ('email', $1, $2, $3, 0)
		 ON CONFLICT (contact_type, contact_value) DO UPDATE SET code_hash = $2, expires_at = $3, attempts = 0`,
		contactValue, string(codeHash), expires)
	if err != nil {
		log.Printf("LoginRequestOTP: db: %v", err)
		http.Error(w, "Failed to send code", http.StatusInternalServerError)
		return
	}
	if err := email.SendLoginOTPEmail(contactValue, code); err != nil {
		log.Printf("LoginRequestOTP: send email: %v", err)
		_, _ = database.DB.Exec(context.Background(), "DELETE FROM login_otps WHERE contact_type = 'email' AND contact_value = $1", contactValue)
		http.Error(w, "Could not send verification code. Please try again later.", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "If this email is registered, you will receive a verification code."})
}

// LoginVerifyOTPRequest is the body for POST /login/verify-otp (email + code).
type LoginVerifyOTPRequest struct {
	Login string `json:"login"`
	Code  string `json:"code"`
}

// LoginVerifyOTP exchanges email + OTP for a JWT. OTP login is email-only.
func LoginVerifyOTP(w http.ResponseWriter, r *http.Request) {
	var req LoginVerifyOTPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	identifier := strings.TrimSpace(req.Login)
	req.Code = strings.TrimSpace(req.Code)
	if identifier == "" || req.Code == "" {
		http.Error(w, "Email and code are required", http.StatusBadRequest)
		return
	}
	if len(req.Code) != 6 {
		http.Error(w, "Invalid or expired code", http.StatusUnauthorized)
		return
	}

	typ := classifyLoginIdentifier(identifier)
	if typ != loginTypeEmail {
		http.Error(w, "OTP login is available for email only.", http.StatusBadRequest)
		return
	}
	contactValue := strings.ToLower(identifier)

	var codeHash string
	var expiresAt time.Time
	var attempts int
	err := database.DB.QueryRow(context.Background(),
		"SELECT code_hash, expires_at, attempts FROM login_otps WHERE contact_type = 'email' AND contact_value = $1",
		contactValue).Scan(&codeHash, &expiresAt, &attempts)
	if err != nil {
		http.Error(w, "Invalid or expired code", http.StatusUnauthorized)
		return
	}
	if attempts >= loginOTPMaxAttempts {
		_, _ = database.DB.Exec(context.Background(), "DELETE FROM login_otps WHERE contact_type = 'email' AND contact_value = $1", contactValue)
		http.Error(w, "Too many attempts. Please request a new code.", http.StatusUnauthorized)
		return
	}
	if time.Now().After(expiresAt) {
		_, _ = database.DB.Exec(context.Background(), "DELETE FROM login_otps WHERE contact_type = 'email' AND contact_value = $1", contactValue)
		http.Error(w, "Invalid or expired code", http.StatusUnauthorized)
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(codeHash), []byte(req.Code)) != nil {
		_, _ = database.DB.Exec(context.Background(),
			"UPDATE login_otps SET attempts = attempts + 1 WHERE contact_type = 'email' AND contact_value = $1", contactValue)
		http.Error(w, "Invalid or expired code", http.StatusUnauthorized)
		return
	}

	_, _ = database.DB.Exec(context.Background(), "DELETE FROM login_otps WHERE contact_type = 'email' AND contact_value = $1", contactValue)

	var userID int
	var role string
	var fullName, shopName *string
	err = database.DB.QueryRow(context.Background(),
		"SELECT id, role, full_name, shop_name FROM users WHERE LOWER(TRIM(email)) = $1", contactValue).Scan(&userID, &role, &fullName, &shopName)
	if err != nil {
		// Account does not exist: return signup token so client can show create-account form.
		signupToken, tokErr := auth.GenerateSignupToken(contactValue)
		if tokErr != nil {
			log.Printf("LoginVerifyOTP: signup token: %v", tokErr)
			http.Error(w, "Failed to complete verification", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"needs_signup":  true,
			"signup_token":  signupToken,
			"email":         contactValue,
		})
		return
	}

	token, err := auth.GenerateToken(userID, role)
	if err != nil {
		http.Error(w, "Failed to generate token", http.StatusInternalServerError)
		return
	}

	setAuthCookie(w, token)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(models.LoginResponse{
		Token:       token,
		Role:        role,
		DisplayName: accountDisplayName(role, fullName, shopName),
	})
}

// LoginGoogleRequest is the body for POST /login/google.
type LoginGoogleRequest struct {
	IDToken string `json:"id_token"`
	// Intent: "customer" (default) auto-creates customer if new; "shopkeeper" returns needs_signup if no account.
	Intent string `json:"intent"`
}

// LoginGoogle verifies a Google ID token and issues an app JWT.
// Existing password / email OTP login is unchanged. New customers are created automatically;
// new shopkeepers get needs_signup so they can complete shop registration.
func LoginGoogle(w http.ResponseWriter, r *http.Request) {
	if len(auth.GoogleClientIDs()) == 0 {
		http.Error(w, "Google Sign-In is not configured", http.StatusServiceUnavailable)
		return
	}

	var req LoginGoogleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	intent := strings.ToLower(strings.TrimSpace(req.Intent))
	if intent == "" {
		intent = "customer"
	}
	if intent != "customer" && intent != "shopkeeper" {
		http.Error(w, "intent must be customer or shopkeeper", http.StatusBadRequest)
		return
	}

	identity, err := auth.VerifyGoogleIDToken(r.Context(), req.IDToken)
	if err != nil {
		log.Printf("LoginGoogle: verify: %v", err)
		msg := "Invalid Google Sign-In. Please try again."
		if strings.Contains(err.Error(), "not configured") {
			msg = "Google Sign-In is not configured"
		}
		http.Error(w, msg, http.StatusUnauthorized)
		return
	}

	var userID int
	var role string
	var fullName, shopName *string
	var existingSub *string

	err = database.DB.QueryRow(context.Background(),
		`SELECT id, role, full_name, shop_name, google_sub FROM users WHERE google_sub = $1`,
		identity.Sub).Scan(&userID, &role, &fullName, &shopName, &existingSub)
	if err == pgx.ErrNoRows {
		err = database.DB.QueryRow(context.Background(),
			`SELECT id, role, full_name, shop_name, google_sub FROM users WHERE LOWER(TRIM(email)) = $1`,
			identity.Email).Scan(&userID, &role, &fullName, &shopName, &existingSub)
	}

	if err == nil {
		// Link Google subject if missing; reject if linked to a different Google account.
		if existingSub != nil && strings.TrimSpace(*existingSub) != "" && *existingSub != identity.Sub {
			http.Error(w, "This email is linked to a different Google account.", http.StatusConflict)
			return
		}
		if existingSub == nil || strings.TrimSpace(*existingSub) == "" {
			_, _ = database.DB.Exec(context.Background(),
				`UPDATE users SET google_sub = $1, updated_at = NOW() WHERE id = $2 AND (google_sub IS NULL OR google_sub = '')`,
				identity.Sub, userID)
		}
		if role == "admin" {
			http.Error(w, "Admin accounts cannot sign in with Google here.", http.StatusForbidden)
			return
		}

		token, tokErr := auth.GenerateToken(userID, role)
		if tokErr != nil {
			http.Error(w, "Failed to generate token", http.StatusInternalServerError)
			return
		}
		setAuthCookie(w, token)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(models.LoginResponse{
			Token:       token,
			Role:        role,
			DisplayName: accountDisplayName(role, fullName, shopName),
		})
		return
	}
	if err != nil && err != pgx.ErrNoRows {
		log.Printf("LoginGoogle: db lookup: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// No user yet
	if intent == "shopkeeper" {
		signupToken, tokErr := auth.GenerateSignupToken(identity.Email)
		if tokErr != nil {
			log.Printf("LoginGoogle: signup token: %v", tokErr)
			http.Error(w, "Failed to complete Google Sign-In", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"needs_signup": true,
			"signup_token": signupToken,
			"email":        identity.Email,
			"full_name":    identity.Name,
		})
		return
	}

	// Auto-create customer
	randomPass := make([]byte, 32)
	if _, err := rand.Read(randomPass); err != nil {
		http.Error(w, "Failed to create account", http.StatusInternalServerError)
		return
	}
	hashedPassword, err := auth.HashPassword(hex.EncodeToString(randomPass))
	if err != nil {
		http.Error(w, "Failed to create account", http.StatusInternalServerError)
		return
	}

	displayName := identity.Name
	if len(displayName) < 2 {
		displayName = "User"
	}

	var newID int
	for attempt := 0; attempt < 5; attempt++ {
		internalUsername := generateInternalUsername()
		newCode := generateUniqueReferralCode()
		err = database.DB.QueryRow(context.Background(),
			`INSERT INTO users (username, full_name, email, phone, password_hash, role, referral_code, google_sub)
			 VALUES ($1, $2, $3, NULL, $4, 'customer', $5, $6) RETURNING id`,
			internalUsername, displayName, identity.Email, hashedPassword, newCode, identity.Sub).Scan(&newID)
		if err == nil {
			break
		}
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			log.Printf("LoginGoogle: unique collision, retry %d: %v", attempt+1, err)
			continue
		}
		break
	}
	if err != nil {
		log.Printf("LoginGoogle: create user: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	token, tokErr := auth.GenerateToken(newID, "customer")
	if tokErr != nil {
		http.Error(w, "Failed to generate token", http.StatusInternalServerError)
		return
	}
	setAuthCookie(w, token)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(models.LoginResponse{
		Token:       token,
		Role:        "customer",
		DisplayName: displayName,
	})
}

const adminOTPExpiry = 10 * time.Minute

// RequestAdminLoginOTPRequest is the body for POST /admin/login/request-otp
type RequestAdminLoginOTPRequest struct {
	Email string `json:"email"`
}

// RequestAdminLoginOTP sends a 6-digit OTP to the given email only if it belongs to an admin user.
func RequestAdminLoginOTP(w http.ResponseWriter, r *http.Request) {
	var req RequestAdminLoginOTPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if req.Email == "" || !emailRegex.MatchString(req.Email) {
		http.Error(w, "Valid email is required", http.StatusBadRequest)
		return
	}

	var userID int
	var role string
	err := database.DB.QueryRow(context.Background(),
		"SELECT id, role FROM users WHERE LOWER(TRIM(email)) = $1", req.Email).Scan(&userID, &role)
	if err != nil || role != "admin" {
		// Same response whether email missing or not admin — no enumeration
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"message": "If this email is registered as an admin, a login code has been sent.",
		})
		return
	}

	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		log.Printf("RequestAdminLoginOTP: rand: %v", err)
		http.Error(w, "Failed to generate code", http.StatusInternalServerError)
		return
	}
	code := fmt.Sprintf("%06d", binary.BigEndian.Uint32(b)%1000000)
	codeHash, err := bcrypt.GenerateFromPassword([]byte(code), 10)
	if err != nil {
		log.Printf("RequestAdminLoginOTP: bcrypt: %v", err)
		http.Error(w, "Failed to generate code", http.StatusInternalServerError)
		return
	}

	expires := time.Now().Add(adminOTPExpiry)
	_, err = database.DB.Exec(context.Background(),
		`INSERT INTO admin_login_otps (email_lower, code_hash, expires_at) VALUES ($1, $2, $3)
		 ON CONFLICT (email_lower) DO UPDATE SET code_hash = $2, expires_at = $3`,
		req.Email, string(codeHash), expires)
	if err != nil {
		log.Printf("RequestAdminLoginOTP: db: %v", err)
		http.Error(w, "Failed to send code", http.StatusInternalServerError)
		return
	}

	if err := email.SendLoginOTPEmail(req.Email, code); err != nil {
		log.Printf("RequestAdminLoginOTP: send email: %v", err)
		// Still return success to avoid email enumeration
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "If this email is registered as an admin, a login code has been sent.",
	})
}

// VerifyAdminLoginOTPRequest is the body for POST /admin/login/verify-otp
type VerifyAdminLoginOTPRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

// VerifyAdminLoginOTP exchanges email + 6-digit code for a JWT (admin only).
func VerifyAdminLoginOTP(w http.ResponseWriter, r *http.Request) {
	var req VerifyAdminLoginOTPRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	req.Code = strings.TrimSpace(req.Code)
	if req.Email == "" || req.Code == "" {
		http.Error(w, "Email and code are required", http.StatusBadRequest)
		return
	}
	if len(req.Code) != 6 {
		http.Error(w, "Invalid code", http.StatusUnauthorized)
		return
	}

	var codeHash string
	var expiresAt time.Time
	err := database.DB.QueryRow(context.Background(),
		"SELECT code_hash, expires_at FROM admin_login_otps WHERE email_lower = $1",
		req.Email).Scan(&codeHash, &expiresAt)
	if err != nil {
		http.Error(w, "Invalid or expired code", http.StatusUnauthorized)
		return
	}
	if time.Now().After(expiresAt) {
		_, _ = database.DB.Exec(context.Background(), "DELETE FROM admin_login_otps WHERE email_lower = $1", req.Email)
		http.Error(w, "Invalid or expired code", http.StatusUnauthorized)
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(codeHash), []byte(req.Code)) != nil {
		http.Error(w, "Invalid or expired code", http.StatusUnauthorized)
		return
	}

	// One-time use: delete OTP
	_, _ = database.DB.Exec(context.Background(), "DELETE FROM admin_login_otps WHERE email_lower = $1", req.Email)

	var userID int
	var role string
	var fullName, shopName *string
	err = database.DB.QueryRow(context.Background(),
		"SELECT id, role, full_name, shop_name FROM users WHERE LOWER(TRIM(email)) = $1", req.Email).Scan(&userID, &role, &fullName, &shopName)
	if err != nil || role != "admin" {
		http.Error(w, "Access denied", http.StatusForbidden)
		return
	}

	token, err := auth.GenerateToken(userID, role)
	if err != nil {
		http.Error(w, "Failed to generate token", http.StatusInternalServerError)
		return
	}
	setAuthCookie(w, token)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(models.LoginResponse{
		Token:       token,
		Role:        role,
		DisplayName: accountDisplayName(role, fullName, shopName),
	})
}

func GetProfile(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var user models.User
	var referralCode *string
	var address *string
	var shopCode *int
	var priceBW, priceColor, doubleSidedFactor *float64
	err := database.DB.QueryRow(context.Background(),
		"SELECT id, username, full_name, email, phone, shop_name, role, address, is_open, shop_code, referral_code, created_at, price_per_page_bw, price_per_page_color, double_sided_factor FROM users WHERE id = $1",
		claims.UserID).Scan(&user.ID, &user.Username, &user.FullName, &user.Email, &user.Phone, &user.ShopName, &user.Role, &address, &user.IsOpen, &shopCode, &referralCode, &user.CreatedAt, &priceBW, &priceColor, &doubleSidedFactor)

	// If SELECT failed (e.g. column missing in old DB), retry without pricing columns
	if err != nil {
		_, _ = database.DB.Exec(context.Background(), "ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_code INT;")
		_, _ = database.DB.Exec(context.Background(), "ALTER TABLE users ADD COLUMN IF NOT EXISTS price_per_page_bw DECIMAL(10,2);")
		_, _ = database.DB.Exec(context.Background(), "ALTER TABLE users ADD COLUMN IF NOT EXISTS price_per_page_color DECIMAL(10,2);")
		_, _ = database.DB.Exec(context.Background(), "ALTER TABLE users ADD COLUMN IF NOT EXISTS double_sided_factor DECIMAL(3,2);")
		shopCode = nil
		priceBW, priceColor, doubleSidedFactor = nil, nil, nil
		err = database.DB.QueryRow(context.Background(),
			"SELECT id, username, full_name, email, phone, shop_name, role, address, is_open, shop_code, referral_code, created_at, price_per_page_bw, price_per_page_color, double_sided_factor FROM users WHERE id = $1",
			claims.UserID).Scan(&user.ID, &user.Username, &user.FullName, &user.Email, &user.Phone, &user.ShopName, &user.Role, &address, &user.IsOpen, &shopCode, &referralCode, &user.CreatedAt, &priceBW, &priceColor, &doubleSidedFactor)
	}
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "User not found", http.StatusNotFound)
			return
		}
		log.Printf("GetProfile: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	if address != nil {
		user.Address = *address
	}

	// Backfill referral_code for customers (e.g. existing users before referral feature, or referred users)
	if user.Role == "customer" && (referralCode == nil || *referralCode == "") {
		newCode := generateUniqueReferralCode()
		for attempt := 0; attempt < 3; attempt++ {
			_, execErr := database.DB.Exec(context.Background(), "UPDATE users SET referral_code = $1 WHERE id = $2", newCode, claims.UserID)
			if execErr == nil {
				referralCode = &newCode
				break
			}
			var pgErr *pgconn.PgError
			if errors.As(execErr, &pgErr) && pgErr.Code == "23505" {
				newCode = generateUniqueReferralCode()
				continue
			}
			log.Printf("GetProfile: backfill referral_code: %v", execErr)
			referralCode = &newCode
			break
		}
		if referralCode == nil {
			c := generateUniqueReferralCode()
			referralCode = &c
		}
	}
	user.ReferralCode = referralCode

	// Backfill shop_code for shopkeepers (6-digit unique code for "enter code" when QR fails)
	if user.Role == "shopkeeper" && shopCode == nil {
		newCode := generateUniqueShopCode()
		for attempt := 0; attempt < 5; attempt++ {
			_, execErr := database.DB.Exec(context.Background(), "UPDATE users SET shop_code = $1 WHERE id = $2", newCode, claims.UserID)
			if execErr == nil {
				shopCode = &newCode
				break
			}
			var pgErr *pgconn.PgError
			if errors.As(execErr, &pgErr) && pgErr.Code == "23505" {
				newCode = generateUniqueShopCode()
				continue
			}
			log.Printf("GetProfile: backfill shop_code: %v", execErr)
			break
		}
		if shopCode == nil {
			c := generateUniqueShopCode()
			shopCode = &c
		}
	}
	user.ShopCode = shopCode

	// Include referral_link for app (base URL from env or placeholder)
	payload := map[string]interface{}{
		"id":            user.ID,
		"display_name":  accountDisplayName(user.Role, user.FullName, user.ShopName),
		"full_name":     user.FullName,
		"email":         user.Email,
		"phone":         user.Phone,
		"shop_name":     user.ShopName,
		"role":          user.Role,
		"address":       user.Address,
		"is_open":       user.IsOpen,
		"shop_code":     user.ShopCode,
		"referral_code": user.ReferralCode,
		"created_at":    user.CreatedAt,
		"updated_at":    user.UpdatedAt,
	}
	// Platform default pricing (env-backed) so clients can display "default" even
	// when shopkeeper hasn't set custom rates.
	payload["platform_price_per_page_bw"] = utils.GetCostPerPageBW()
	payload["platform_price_per_page_color"] = utils.GetCostPerPageColor()
	if user.Role == "shopkeeper" {
		payload["price_per_page_bw"] = priceBW
		payload["price_per_page_color"] = priceColor
		payload["double_sided_factor"] = doubleSidedFactor
	}
	if user.ReferralCode != nil && *user.ReferralCode != "" {
		baseURL := os.Getenv("REFERRAL_BASE_URL")
		if baseURL == "" {
			baseURL = "https://qprint.co.in"
		}
		payload["referral_link"] = strings.TrimSuffix(baseURL, "/") + "/r/" + *user.ReferralCode
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(payload)
}

var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)

func UpdateProfile(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req models.UpdateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("UpdateProfile: invalid request body: %v", err)
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Validate email format if provided
	if req.Email != "" && !emailRegex.MatchString(req.Email) {
		http.Error(w, "Invalid email format", http.StatusBadRequest)
		return
	}

	var role string
	var passwordHash string
	err := database.DB.QueryRow(context.Background(),
		"SELECT role, password_hash FROM users WHERE id = $1", claims.UserID).Scan(&role, &passwordHash)
	if err != nil {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	// When changing password, require current password
	if req.Password != "" {
		if req.CurrentPassword == "" {
			http.Error(w, "Current password is required to set a new password", http.StatusBadRequest)
			return
		}
		if !auth.CheckPasswordHash(req.CurrentPassword, passwordHash) {
			http.Error(w, "Current password is incorrect", http.StatusUnauthorized)
			return
		}
	}

	// Email uniqueness: another user may not have this email
	if req.Email != "" {
		var otherID int
		err := database.DB.QueryRow(context.Background(),
			"SELECT id FROM users WHERE TRIM(LOWER(email)) = TRIM(LOWER($1)) AND id != $2",
			req.Email, claims.UserID).Scan(&otherID)
		if err == nil {
			http.Error(w, "This email is already in use by another account", http.StatusConflict)
			return
		}
	}

	if req.Password != "" {
		hashedPassword, err := auth.HashPassword(req.Password)
		if err != nil {
			http.Error(w, "Failed to hash password", http.StatusInternalServerError)
			return
		}
		if role == "shopkeeper" {
			_, err = database.DB.Exec(context.Background(),
				`UPDATE users SET address = $1, password_hash = $2, shop_name = NULLIF(TRIM($3), ''),
				 full_name = NULLIF(TRIM($4), ''), email = NULLIF(TRIM($5), ''), phone = NULLIF(TRIM($6), ''), updated_at = NOW() WHERE id = $7`,
				req.Address, hashedPassword, req.ShopName, req.FullName, req.Email, req.Phone, claims.UserID)
		} else {
			_, err = database.DB.Exec(context.Background(),
				`UPDATE users SET address = $1, password_hash = $2,
				 full_name = NULLIF(TRIM($3), ''), email = NULLIF(TRIM($4), ''), phone = NULLIF(TRIM($5), ''), updated_at = NOW() WHERE id = $6`,
				req.Address, hashedPassword, req.FullName, req.Email, req.Phone, claims.UserID)
		}
		if err != nil {
			log.Printf("UpdateProfile: database error: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}
	} else {
		if role == "shopkeeper" {
			_, err = database.DB.Exec(context.Background(),
				`UPDATE users SET address = $1, shop_name = NULLIF(TRIM($2), ''),
				 full_name = NULLIF(TRIM($3), ''), email = NULLIF(TRIM($4), ''), phone = NULLIF(TRIM($5), ''), updated_at = NOW() WHERE id = $6`,
				req.Address, req.ShopName, req.FullName, req.Email, req.Phone, claims.UserID)
		} else {
			_, err = database.DB.Exec(context.Background(),
				`UPDATE users SET address = $1,
				 full_name = NULLIF(TRIM($2), ''), email = NULLIF(TRIM($3), ''), phone = NULLIF(TRIM($4), ''), updated_at = NOW() WHERE id = $5`,
				req.Address, req.FullName, req.Email, req.Phone, claims.UserID)
		}
		if err != nil {
			log.Printf("UpdateProfile: database error: %v", err)
			http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
			return
		}
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Profile updated successfully"})
}

func ToggleShopStatus(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Only shopkeepers can change shop open/closed status
	if claims.Role != "shopkeeper" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var req struct {
		IsOpen bool `json:"is_open"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	_, err := database.DB.Exec(context.Background(),
		"UPDATE users SET is_open = $1 WHERE id = $2",
		req.IsOpen, claims.UserID)

	if err != nil {
		log.Printf("ToggleShopStatus: database error: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Shop status updated successfully"})
}

// UpdateShopPricing allows shopkeepers to set their per-page rates and optional double-sided factor.
// Security: only role shopkeeper; validated ranges; rate-limited by route group.
func UpdateShopPricing(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	if claims.Role != "shopkeeper" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var req models.UpdateShopPricingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	const maxPrice = 9999.99
	// Validate and build update: only update columns that are present; use -1 as sentinel for "clear" (set NULL)
	var setClauses []string
	var args []interface{}
	argNum := 1

	if req.PricePerPageBW != nil {
		if *req.PricePerPageBW < 0 {
			if *req.PricePerPageBW != -1 {
				http.Error(w, "price_per_page_bw must be non-negative or -1 to clear", http.StatusBadRequest)
				return
			}
			setClauses = append(setClauses, fmt.Sprintf("price_per_page_bw = $%d", argNum))
			args = append(args, nil)
			argNum++
		} else if *req.PricePerPageBW > maxPrice {
			http.Error(w, "price_per_page_bw cannot exceed 9999.99", http.StatusBadRequest)
			return
		} else {
			setClauses = append(setClauses, fmt.Sprintf("price_per_page_bw = $%d", argNum))
			args = append(args, *req.PricePerPageBW)
			argNum++
		}
	}
	if req.PricePerPageColor != nil {
		if *req.PricePerPageColor < 0 {
			if *req.PricePerPageColor != -1 {
				http.Error(w, "price_per_page_color must be non-negative or -1 to clear", http.StatusBadRequest)
				return
			}
			setClauses = append(setClauses, fmt.Sprintf("price_per_page_color = $%d", argNum))
			args = append(args, nil)
			argNum++
		} else if *req.PricePerPageColor > maxPrice {
			http.Error(w, "price_per_page_color cannot exceed 9999.99", http.StatusBadRequest)
			return
		} else {
			setClauses = append(setClauses, fmt.Sprintf("price_per_page_color = $%d", argNum))
			args = append(args, *req.PricePerPageColor)
			argNum++
		}
	}
	if req.DoubleSidedFactor != nil {
		if *req.DoubleSidedFactor <= 0 || *req.DoubleSidedFactor > 1 {
			if *req.DoubleSidedFactor != -1 {
				http.Error(w, "double_sided_factor must be in (0, 1] or -1 to clear", http.StatusBadRequest)
				return
			}
			setClauses = append(setClauses, fmt.Sprintf("double_sided_factor = $%d", argNum))
			args = append(args, nil)
			argNum++
		} else {
			setClauses = append(setClauses, fmt.Sprintf("double_sided_factor = $%d", argNum))
			args = append(args, *req.DoubleSidedFactor)
			argNum++
		}
	}

	if len(setClauses) == 0 {
		http.Error(w, "Provide at least one of price_per_page_bw, price_per_page_color, double_sided_factor", http.StatusBadRequest)
		return
	}

	args = append(args, claims.UserID)
	query := fmt.Sprintf("UPDATE users SET %s, updated_at = NOW() WHERE id = $%d AND role = 'shopkeeper'",
		strings.Join(setClauses, ", "), argNum)
	result, err := database.DB.Exec(context.Background(), query, args...)
	if err != nil {
		log.Printf("UpdateShopPricing: database error: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	if result.RowsAffected() == 0 {
		http.Error(w, "User not found or not a shopkeeper", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Pricing updated successfully"})
}

// ShopHeartbeat marks a shopkeeper as active (app running) and opens the shop.
// Intended to be called periodically by the shopkeeper app while running.
func ShopHeartbeat(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	if claims.Role != "shopkeeper" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	_, err := database.DB.Exec(context.Background(),
		`UPDATE users 
		 SET is_open = TRUE, last_app_heartbeat_at = NOW()
		 WHERE id = $1 AND role = 'shopkeeper'`,
		claims.UserID)
	if err != nil {
		log.Printf("ShopHeartbeat: database error: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// ForgotPassword handles password recovery request
func ForgotPassword(w http.ResponseWriter, r *http.Request) {
	var req models.ForgotPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("ForgotPassword: invalid request body: %v", err)
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.Email) == "" {
		http.Error(w, "Email is required", http.StatusBadRequest)
		return
	}

	// Check if user exists with this email
	var userID int
	err := database.DB.QueryRow(context.Background(),
		"SELECT id FROM users WHERE email = $1", req.Email).Scan(&userID)
	if err != nil {
		// Don't reveal if email exists or not for security
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"message": "If the email exists, a password reset link has been sent"})
		return
	}

	// Generate reset token (plain for email link; store hashed + selector for lookup)
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}
	token := hex.EncodeToString(tokenBytes)
	tokenSelector := token[:8]
	tokenHash, err := auth.HashPassword(token)
	if err != nil {
		log.Printf("ForgotPassword: hash token: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Store hashed token and selector (expires in 30 minutes)
	expiresAt := time.Now().Add(30 * time.Minute)
	_, err = database.DB.Exec(context.Background(),
		"INSERT INTO password_reset_tokens (user_id, token, token_selector, expires_at) VALUES ($1, $2, $3, $4)",
		userID, tokenHash, tokenSelector, expiresAt)
	if err != nil {
		log.Printf("ForgotPassword: insert token: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Send email with reset link
	err = email.SendPasswordResetEmail(req.Email, token)
	if err != nil {
		log.Printf("Failed to send password reset email: %v", err)
		// Still return success to prevent email enumeration
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"message": "If the email exists, a password reset link has been sent to your email address",
	})
}

// ResetPassword handles password reset with token
func ResetPassword(w http.ResponseWriter, r *http.Request) {
	var req models.ResetPasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("ResetPassword: invalid request body: %v", err)
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.Token) == "" {
		http.Error(w, "Reset token is required", http.StatusBadRequest)
		return
	}

	if len(req.Password) < 8 {
		http.Error(w, "Password must be at least 8 characters", http.StatusBadRequest)
		return
	}

	// Look up by token selector and atomically claim the token (prevent race: two requests with same token both succeeding)
	if len(req.Token) < 8 {
		http.Error(w, "Invalid or expired reset token", http.StatusBadRequest)
		return
	}
	tokenSelector := req.Token[:8]
	var userID int
	var tokenHash string
	var expiresAt time.Time
	err := database.DB.QueryRow(context.Background(),
		`UPDATE password_reset_tokens SET used = true WHERE token_selector = $1 AND used = false
		 RETURNING user_id, token, expires_at`,
		tokenSelector).Scan(&userID, &tokenHash, &expiresAt)

	if err != nil {
		http.Error(w, "Invalid or expired reset token", http.StatusBadRequest)
		return
	}

	if time.Now().After(expiresAt) {
		http.Error(w, "Reset token has expired", http.StatusBadRequest)
		return
	}

	if !auth.CheckPasswordHash(req.Token, tokenHash) {
		http.Error(w, "Invalid or expired reset token", http.StatusBadRequest)
		return
	}

	// Hash new password
	hashedPassword, err := auth.HashPassword(req.Password)
	if err != nil {
		http.Error(w, "Failed to hash password", http.StatusInternalServerError)
		return
	}

	// Update password
	_, err = database.DB.Exec(context.Background(),
		"UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2",
		hashedPassword, userID)
	if err != nil {
		log.Printf("ResetPassword: database error: %v", err)
		http.Error(w, "An error occurred. Please try again.", http.StatusInternalServerError)
		return
	}

	// Invalidate all reset tokens for this user (security: one-time use and no old links valid)
	_, _ = database.DB.Exec(context.Background(),
		"DELETE FROM password_reset_tokens WHERE user_id = $1", userID)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Password reset successfully"})
}

// Logout clears the auth cookie. Call with credentials (cookie or Bearer). Protected by AuthMiddleware.
func Logout(w http.ResponseWriter, r *http.Request) {
	clearAuthCookie(w)
	w.WriteHeader(http.StatusOK)
}

// DeleteMyAccount allows users to delete their own account
func DeleteMyAccount(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Require password confirmation
	var req struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if strings.TrimSpace(req.Password) == "" {
		http.Error(w, "Password is required to confirm account deletion", http.StatusBadRequest)
		return
	}

	// Verify password
	var passwordHash string
	var role string
	err := database.DB.QueryRow(context.Background(),
		"SELECT password_hash, role FROM users WHERE id = $1", claims.UserID).Scan(&passwordHash, &role)
	if err != nil {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}

	if !auth.CheckPasswordHash(req.Password, passwordHash) {
		http.Error(w, "Invalid password", http.StatusUnauthorized)
		return
	}

	// Prevent admin self-deletion
	if role == "admin" {
		http.Error(w, "Admin accounts cannot be deleted through this endpoint", http.StatusForbidden)
		return
	}

	userID := claims.UserID

	// Start transaction
	tx, err := database.DB.Begin(context.Background())
	if err != nil {
		log.Printf("DeleteMyAccount: begin tx: %v", err)
		http.Error(w, "An error occurred", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(context.Background())

	// Load all files for this user (id, file_path, status, payment_order_id)
	rows, err := tx.Query(context.Background(),
		"SELECT id, file_path, status, payment_order_id FROM files WHERE user_id = $1", userID)
	if err != nil {
		log.Printf("DeleteMyAccount: get files: %v", err)
		http.Error(w, "An error occurred", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var filePaths []string
	// Refund once per order: map payment_order_id -> one fileID (for orders that have any non-downloaded file)
	orderToRefund := make(map[int]int) // payment_order_id -> fileID
	for rows.Next() {
		var fileID int
		var path string
		var status string
		var paymentOrderID *int
		if err := rows.Scan(&fileID, &path, &status, &paymentOrderID); err == nil {
			if path != "" {
				filePaths = append(filePaths, path)
			}
			if status != "downloaded" && paymentOrderID != nil {
				if _, ok := orderToRefund[*paymentOrderID]; !ok {
					orderToRefund[*paymentOrderID] = fileID
				}
			}
		}
	}
	for poID, fID := range orderToRefund {
		refundForFile(refundContext{
			UserID:         userID,
			FileID:         fID,
			PaymentOrderID: poID,
			Reason:         "Customer account deleted",
		})
	}
	// Mark all non-downloaded files as withdrawn (single order = one refund, all files updated)
	_, _ = tx.Exec(context.Background(), `UPDATE files SET status = 'withdrawn' WHERE user_id = $1 AND status != 'downloaded'`, userID)

	// Delete password reset tokens
	_, err = tx.Exec(context.Background(),
		"DELETE FROM password_reset_tokens WHERE user_id = $1", userID)
	if err != nil {
		log.Printf("DeleteMyAccount: delete reset tokens: %v", err)
		http.Error(w, "An error occurred", http.StatusInternalServerError)
		return
	}

	// Delete wallet_transactions and wallet_topup_orders
	_, err = tx.Exec(context.Background(),
		"DELETE FROM wallet_transactions WHERE user_id = $1", userID)
	if err != nil {
		log.Printf("DeleteMyAccount: delete wallet_transactions: %v", err)
		http.Error(w, "An error occurred", http.StatusInternalServerError)
		return
	}
	_, err = tx.Exec(context.Background(),
		"DELETE FROM wallet_topup_orders WHERE user_id = $1", userID)
	if err != nil {
		log.Printf("DeleteMyAccount: delete wallet_topup_orders: %v", err)
		http.Error(w, "An error occurred", http.StatusInternalServerError)
		return
	}

	// Set user_id to NULL for payment orders (preserve financial records)
	_, err = tx.Exec(context.Background(),
		"UPDATE payment_orders SET user_id = NULL WHERE user_id = $1", userID)
	if err != nil {
		log.Printf("DeleteMyAccount: update payment orders: %v", err)
		http.Error(w, "An error occurred", http.StatusInternalServerError)
		return
	}

	// Delete files
	_, err = tx.Exec(context.Background(),
		"DELETE FROM files WHERE user_id = $1", userID)
	if err != nil {
		log.Printf("DeleteMyAccount: delete files: %v", err)
		http.Error(w, "An error occurred", http.StatusInternalServerError)
		return
	}

	// Remove referral data that references this user (so self-delete works for accounts created via referral)
	execReferralCleanup := func(query string, args ...interface{}) bool {
		_, execErr := tx.Exec(context.Background(), query, args...)
		if execErr != nil {
			var pgErr *pgconn.PgError
			if errors.As(execErr, &pgErr) && pgErr.Code == "42P01" {
				log.Printf("DeleteMyAccount: referral table not present, skipping: %v", execErr)
				return true
			}
			log.Printf("DeleteMyAccount: referral cleanup: %v", execErr)
			http.Error(w, "An error occurred", http.StatusInternalServerError)
			return false
		}
		return true
	}
	if !execReferralCleanup("DELETE FROM referral_invite_log WHERE referrer_id = $1", userID) {
		return
	}
	// Only delete rows where this user was the referrer. Do NOT delete where they were referee:
	// those rows (with status='credited' and referee_email) must be kept so the same email
	// cannot get referee bonus again after re-registering (one referral bonus per email in lifetime).
	if !execReferralCleanup("DELETE FROM referrals WHERE referrer_id = $1", userID) {
		return
	}

	// Delete user
	_, err = tx.Exec(context.Background(),
		"DELETE FROM users WHERE id = $1", userID)
	if err != nil {
		log.Printf("DeleteMyAccount: delete user: %v", err)
		http.Error(w, "An error occurred", http.StatusInternalServerError)
		return
	}

	// Commit transaction
	if err = tx.Commit(context.Background()); err != nil {
		log.Printf("DeleteMyAccount: commit: %v", err)
		http.Error(w, "An error occurred", http.StatusInternalServerError)
		return
	}

	// Delete files from storage (after successful DB commit). Use storage layer so both local and S3 work.
	for _, path := range filePaths {
		if err := fileStorage.Delete(context.Background(), path); err != nil {
			log.Printf("DeleteMyAccount: failed to delete file %s: %v", path, err)
			// Continue even if file deletion fails
		}
	}

	// Clear auth cookie
	clearAuthCookie(w)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Account deleted successfully"})
}

// DeleteDataPage serves a public HTML page for Google Play "Delete data" link requirement.
// Users who collect account data (e.g. username/password) must provide a URL where users can request deletion.
func DeleteDataPage(w http.ResponseWriter, r *http.Request) {
	supportEmail := os.Getenv("SUPPORT_EMAIL")
	if supportEmail == "" {
		supportEmail = "support@qprint.co.in"
	}
	// Escape to prevent XSS if SUPPORT_EMAIL were ever set to attacker-controlled value
	supportEmail = html.EscapeString(supportEmail)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	htmlContent := `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Delete your data – qprint (QprintSolutions)</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 560px; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; color: #1a1a1a; }
    h1 { font-size: 1.25rem; }
    ol { padding-left: 1.25rem; }
    li { margin-bottom: 0.5rem; }
    a { color: #0066cc; }
    .email { word-break: break-all; }
  </style>
</head>
<body>
  <h1>Delete your qprint account and data</h1>
  <p>qprint is made by <strong>QprintSolutions</strong>. We store your account data (email, phone, and related print history) when you use the app.</p>
  <h2>How to delete your data</h2>
  <ol>
    <li><strong>From the app (recommended):</strong> Open the qprint app, go to <strong>Profile</strong>, tap <strong>Delete Account</strong>, and confirm with your password. This permanently deletes your account and associated data.</li>
    <li><strong>If you cannot access the app:</strong> Email us at <a class="email" href="mailto:` + supportEmail + `">` + supportEmail + `</a> with the email or phone you used to register. We will process your deletion request within 30 days.</li>
  </ol>
  <p>After deletion, we do not retain your account or personal data for longer than necessary for legal or operational requirements.</p>
</body>
</html>`
	w.Write([]byte(htmlContent))
}
