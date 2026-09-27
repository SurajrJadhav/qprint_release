package auth

import (
	"context"
	"net/http"
	"os"
	"strings"
)

// BearerOnly returns true when auth must use Bearer token only (no cookie).
// In production this is true by default; set SKIP_AUTH_COOKIE=false to allow cookie auth.
// In development, cookie is allowed unless SKIP_AUTH_COOKIE=true.
func BearerOnly() bool {
	if os.Getenv("SKIP_AUTH_COOKIE") == "true" {
		return true
	}
	if os.Getenv("ENVIRONMENT") == "production" && os.Getenv("SKIP_AUTH_COOKIE") != "false" {
		return true
	}
	return false
}

type contextKey string

const UserKey contextKey = "user"

// CookieName is the name of the httpOnly auth cookie set on login (same as frontend expectation).
const CookieName = "qprint_token"

func AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := ""
		authHeader := r.Header.Get("Authorization")
		if authHeader != "" {
			parts := strings.Split(authHeader, " ")
			if len(parts) == 2 && parts[0] == "Bearer" {
				token = parts[1]
			}
		}
		if token == "" && !BearerOnly() {
			if c, err := r.Cookie(CookieName); err == nil && c.Value != "" {
				token = c.Value
			}
		}
		if token == "" {
			http.Error(w, "Authorization required", http.StatusUnauthorized)
			return
		}

		claims, err := ValidateToken(token)
		if err != nil {
			http.Error(w, "Invalid token", http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(r.Context(), UserKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
