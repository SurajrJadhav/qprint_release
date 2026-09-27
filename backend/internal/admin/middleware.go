package admin

import (
	"context"
	"net/http"
	"strings"

	"backend/internal/auth"
)

// AdminMiddleware ensures the user is authenticated and has admin role.
// Accepts token from Authorization Bearer or from auth cookie (same as AuthMiddleware).
func AdminMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := ""
		authHeader := r.Header.Get("Authorization")
		if authHeader != "" {
			parts := strings.Split(authHeader, " ")
			if len(parts) == 2 && parts[0] == "Bearer" {
				token = parts[1]
			}
		}
		if token == "" && !auth.BearerOnly() {
			if c, err := r.Cookie(auth.CookieName); err == nil && c.Value != "" {
				token = c.Value
			}
		}
		if token == "" {
			http.Error(w, "Authorization required", http.StatusUnauthorized)
			return
		}

		claims, err := auth.ValidateToken(token)
		if err != nil {
			http.Error(w, "Invalid token", http.StatusUnauthorized)
			return
		}

		if claims.Role != "admin" {
			http.Error(w, "Admin access required", http.StatusForbidden)
			return
		}

		ctx := context.WithValue(r.Context(), auth.UserKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
