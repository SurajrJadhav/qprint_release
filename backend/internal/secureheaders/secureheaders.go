package secureheaders

import (
	"net/http"
	"os"
)

// Middleware adds security headers to responses. In production (when not development/test),
// it also adds HSTS. When behind a TLS-terminating proxy, set PRODUCTION=1 or do not set
// ENVIRONMENT=development / TEST_MODE=true.
func Middleware(next http.Handler) http.Handler {
	production := os.Getenv("ENVIRONMENT") != "development" && os.Getenv("TEST_MODE") != "true"
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		// Content-Security-Policy: mitigates XSS; default-src 'none' for API, allow inline styles for /delete-data HTML page only.
		w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'")
		// Permissions-Policy: restrict browser features/APIs (camera, mic, geolocation, etc.) when origin is this API.
		w.Header().Set("Permissions-Policy", "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()")
		// Prevent caching of responses (API and HTML may contain sensitive data). ZAP: use "no-cache, no-store, must-revalidate".
		w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate, private")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("Expires", "0")
		if production {
			w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		next.ServeHTTP(w, r)
	})
}
