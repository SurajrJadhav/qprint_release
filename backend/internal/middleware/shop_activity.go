package middleware

import (
	"backend/internal/auth"
	"backend/internal/database"
	"context"
	"net/http"
	"strings"
)

// ShopkeeperActivity updates last_web_activity_at when requests come from web clients.
// This supports auto-close logic when the shopkeeper closes the browser/tab (inactivity timeout).
//
// Clients should send: X-Platform: web | android | ios
// We only record web activity here; app activity is handled by /shop/heartbeat.
func ShopkeeperActivity(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
		if ok && claims != nil && claims.Role == "shopkeeper" {
			platform := strings.ToLower(strings.TrimSpace(r.Header.Get("X-Platform")))
			if platform == "web" {
				// Best-effort update; do not block the request on failures.
				_, _ = database.DB.Exec(context.Background(),
					`UPDATE users SET last_web_activity_at = NOW() WHERE id = $1 AND role = 'shopkeeper'`,
					claims.UserID)
			}
		}
		next.ServeHTTP(w, r)
	})
}

