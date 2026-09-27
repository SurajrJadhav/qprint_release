package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"backend/internal/database"
)

// GetAppDownloads returns app download links and "coming soon" flags for Windows, Android, iOS.
// Public endpoint — no auth required.
func GetAppDownloads(w http.ResponseWriter, r *http.Request) {
	var windowsURL, androidURL, iosURL string
	var windowsComingSoon, androidComingSoon, iosComingSoon bool
	err := database.DB.QueryRow(context.Background(),
		`SELECT COALESCE(windows_shopkeeper_url,''), COALESCE(android_customer_url,''), COALESCE(ios_customer_url,''),
		 COALESCE(windows_coming_soon, true), COALESCE(android_coming_soon, true), COALESCE(ios_coming_soon, true)
		 FROM app_download_links WHERE id = 1`).
		Scan(&windowsURL, &androidURL, &iosURL, &windowsComingSoon, &androidComingSoon, &iosComingSoon)
	if err != nil {
		windowsURL = ""
		androidURL = ""
		iosURL = ""
		windowsComingSoon = true
		androidComingSoon = true
		iosComingSoon = true
	}

	out := map[string]interface{}{
		"windows_shopkeeper_url": windowsURL,
		"android_customer_url":   androidURL,
		"ios_customer_url":       iosURL,
		"windows_coming_soon":    windowsComingSoon,
		"android_coming_soon":    androidComingSoon,
		"ios_coming_soon":        iosComingSoon,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(out)
}
