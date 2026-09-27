package handlers

import (
	"backend/internal/auth"
	"backend/internal/notifications"
	"encoding/json"
	"net/http"
)

// RegisterFCMTokenRequest is the body for POST /notifications/register-token
type RegisterFCMTokenRequest struct {
	FCMToken string `json:"fcm_token"`
	Platform string `json:"platform"` // "android" or "ios", default "android"
}

// RegisterFCMToken saves the device FCM token for the current user (customer app).
func RegisterFCMToken(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value(auth.UserKey).(*auth.Claims)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	if claims.Role != "customer" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	var req RegisterFCMTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.FCMToken == "" {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"message": "Token cleared or omitted"})
		return
	}
	if req.Platform == "" {
		req.Platform = "android"
	}
	if req.Platform != "android" && req.Platform != "ios" {
		req.Platform = "android"
	}

	if err := notifications.RegisterToken(r.Context(), claims.UserID, req.FCMToken, req.Platform); err != nil {
		http.Error(w, "Failed to save token", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"message": "Token registered"})
}
