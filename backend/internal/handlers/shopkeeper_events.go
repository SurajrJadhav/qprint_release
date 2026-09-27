package handlers

import (
	"backend/internal/auth"
	"backend/internal/database"
	"context"
	"net/http"

	"backend/internal/shopkeeperstream"
)

// ShopkeeperEventsStream handles GET /shopkeeper/events (SSE stream for new queue notifications).
// Requires auth; only shopkeepers can connect. Shop ID is the authenticated user's ID.
func ShopkeeperEventsStream(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var role string
	if err := database.DB.QueryRow(context.Background(),
		"SELECT role FROM users WHERE id = $1", claims.UserID).Scan(&role); err != nil || role != "shopkeeper" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	shopID := claims.UserID
	shopkeeperstream.Serve(w, r, shopID)
}
