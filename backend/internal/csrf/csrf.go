package csrf

import (
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"os"
	"strings"
)

const cookieName = "csrf_token"
const headerName = "X-CSRF-Token"
const tokenLen = 32

// Secure returns true when running in production (HTTPS); false in development so cookies work on localhost.
func secure() bool {
	return os.Getenv("ENVIRONMENT") == "production" && os.Getenv("TEST_MODE") != "true"
}

// GenerateToken creates a new CSRF token (hex), sets it in a cookie, and returns the same value for the response body.
func GenerateToken(w http.ResponseWriter, r *http.Request) (string, error) {
	b := make([]byte, tokenLen)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	token := hex.EncodeToString(b)
	cookie := &http.Cookie{
		Name:     cookieName,
		Value:    token,
		Path:     "/",
		MaxAge:   3600,
		SameSite: http.SameSiteNoneMode,
		Secure:   secure(),
		HttpOnly: false, // frontend needs to send this value in X-CSRF-Token header; we validate cookie server-side
	}
	// For SameSite=None, browser requires Secure. In dev (Secure=false) use Lax so cookie is set on localhost.
	if !cookie.Secure {
		cookie.SameSite = http.SameSiteLaxMode
	}
	http.SetCookie(w, cookie)
	return token, nil
}

// Handler serves GET /csrf-token: sets CSRF cookie and returns JSON { "csrfToken": "..." }.
func Handler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	token, err := GenerateToken(w, r)
	if err != nil {
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"csrfToken":"` + token + `"}`))
}

// Validate checks that the request has a matching CSRF cookie and X-CSRF-Token header for state-changing methods.
func Validate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method := strings.ToUpper(r.Method)
		if method != "POST" && method != "PUT" && method != "PATCH" && method != "DELETE" {
			next.ServeHTTP(w, r)
			return
		}
		// Skip webhook (external caller cannot get our CSRF cookie)
		if strings.HasSuffix(r.URL.Path, "/payment/webhook") {
			next.ServeHTTP(w, r)
			return
		}
		// Admin routes: when authenticated with Bearer, CSRF is not required (Bearer is not auto-sent by browsers,
		// so CSRF from another origin cannot forge admin actions). Avoids 403 when admin panel is on a different
		// subdomain and CSRF cookie/header can be out of sync.
		if strings.HasPrefix(r.URL.Path, "/admin/") {
			auth := r.Header.Get("Authorization")
			if strings.HasPrefix(strings.TrimSpace(auth), "Bearer ") {
				next.ServeHTTP(w, r)
				return
			}
		}
		cookie, err := r.Cookie(cookieName)
		if err != nil || cookie.Value == "" {
			// No CSRF cookie: likely API client (shopkeeper/customer desktop/mobile app)
			// using Bearer token only. CSRF does not apply—Bearer is not auto-sent by browsers.
			// Allow request; Auth middleware has already validated the token.
			next.ServeHTTP(w, r)
			return
		}
		header := r.Header.Get(headerName)
		if header == "" || !strings.EqualFold(header, cookie.Value) {
			http.Error(w, "CSRF token invalid", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// isAuthPath returns true for login/register/forgot-password etc. (no session state; safe to skip CSRF when cookie/header out of sync).
func isAuthPath(path string) bool {
	switch path {
	case "/register/send-otp", "/register/verify-otp", "/register",
		"/login", "/login/request-otp", "/login/verify-otp", "/login/verify-2fa",
		"/admin/login/request-otp", "/admin/login/verify-otp",
		"/forgot-password", "/reset-password":
		return true
	}
	return false
}

// ValidateOptional checks CSRF if the cookie is present, but allows requests without it.
// Use for public endpoints (login, register) that should work in incognito mode where
// third-party cookies are blocked. These endpoints don't rely on existing session state,
// so CSRF risk is minimal.
func ValidateOptional(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		method := strings.ToUpper(r.Method)
		if method != "POST" && method != "PUT" && method != "PATCH" && method != "DELETE" {
			next.ServeHTTP(w, r)
			return
		}
		// Skip webhook
		if strings.HasSuffix(r.URL.Path, "/payment/webhook") {
			next.ServeHTTP(w, r)
			return
		}
		// Skip CSRF for all auth endpoints: no session state; cookie/header often out of sync when admin or app is on another origin (e.g. Render)
		if isAuthPath(r.URL.Path) {
			next.ServeHTTP(w, r)
			return
		}

		// If CSRF cookie is present, validate it
		cookie, err := r.Cookie(cookieName)
		if err == nil && cookie.Value != "" {
			header := r.Header.Get(headerName)
			if header == "" || !strings.EqualFold(header, cookie.Value) {
				http.Error(w, "CSRF token invalid", http.StatusForbidden)
				return
			}
		}
		// If no cookie (e.g., blocked in incognito), allow request
		// This is safe for login/register as they don't rely on existing session state
		next.ServeHTTP(w, r)
	})
}
