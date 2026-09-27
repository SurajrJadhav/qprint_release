package notifications

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"strconv"
	"sync"
	"time"

	"backend/internal/database"

	"golang.org/x/oauth2/google"
)

const fcmScope = "https://www.googleapis.com/auth/firebase.messaging"
const radiusKm = 10

// serviceAccountKey is used to parse project_id from the JSON file.
type serviceAccountKey struct {
	ProjectID string `json:"project_id"`
}

var (
	projectID    string
	creds        *google.Credentials
	httpClient   *http.Client
	initOnce     sync.Once
	initErr      error
)

func initFCM() {
	initOnce.Do(func() {
		val := os.Getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
		if val == "" {
			val = os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")
		}
		if val == "" {
			log.Println("FIREBASE_SERVICE_ACCOUNT_JSON (or GOOGLE_APPLICATION_CREDENTIALS) not set; push notifications disabled")
			return
		}
		var jsonData []byte
		// If value looks like JSON (starts with '{'), use it as inline JSON (e.g. on Render: paste entire JSON in env var).
		// Otherwise treat as file path (e.g. local: /path/to/key.json or C:\path\to\key.json).
		if len(val) > 0 && val[0] == '{' {
			jsonData = []byte(val)
		} else {
			var err error
			jsonData, err = os.ReadFile(val)
			if err != nil {
				initErr = fmt.Errorf("reading service account JSON file: %w", err)
				log.Printf("notifications: %v", initErr)
				return
			}
		}
		var key serviceAccountKey
		if err := json.Unmarshal(jsonData, &key); err != nil || key.ProjectID == "" {
			log.Printf("notifications: invalid service account JSON (missing project_id)")
			return
		}
		projectID = key.ProjectID
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		var err error
		creds, err = google.CredentialsFromJSON(ctx, jsonData, fcmScope)
		if err != nil {
			initErr = fmt.Errorf("credentials from JSON: %w", err)
			log.Printf("notifications: %v", initErr)
			return
		}
		httpClient = &http.Client{Timeout: 15 * time.Second}
	})
}

// getAccessToken returns a valid OAuth2 access token for FCM (cached by TokenSource).
func getAccessToken(ctx context.Context) (string, error) {
	if creds == nil {
		return "", fmt.Errorf("FCM not initialized")
	}
	token, err := creds.TokenSource.Token()
	if err != nil {
		return "", err
	}
	return token.AccessToken, nil
}

// RegisterToken saves or updates the FCM token for a user (e.g. android/ios).
// Replaces any existing token for that user+platform.
func RegisterToken(ctx context.Context, userID int, token, platform string) error {
	if token == "" {
		return nil
	}
	if platform == "" {
		platform = "android"
	}
	_, err := database.DB.Exec(ctx,
		`INSERT INTO fcm_tokens (user_id, platform, fcm_token, updated_at)
		 VALUES ($1, $2, $3, NOW())
		 ON CONFLICT (user_id, platform) DO UPDATE SET fcm_token = $3, updated_at = NOW()`,
		userID, platform, token)
	return err
}

// getTokensForUser returns FCM tokens for the given user (all platforms).
func getTokensForUser(ctx context.Context, userID int) ([]string, error) {
	rows, err := database.DB.Query(ctx,
		"SELECT fcm_token FROM fcm_tokens WHERE user_id = $1 AND fcm_token != ''", userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var tokens []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			continue
		}
		tokens = append(tokens, t)
	}
	return tokens, rows.Err()
}

// sendToTokens sends a push notification via FCM HTTP v1 API (one request per token).
func sendToTokens(tokens []string, title, body string, data map[string]string) {
	if len(tokens) == 0 {
		return
	}
	initFCM()
	if projectID == "" || creds == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	accessToken, err := getAccessToken(ctx)
	if err != nil {
		log.Printf("notifications: get access token: %v", err)
		return
	}
	url := "https://fcm.googleapis.com/v1/projects/" + projectID + "/messages:send"
	for _, token := range tokens {
		// FCM v1: one message per request; "message" contains "token", "notification", "data"
		payload := map[string]interface{}{
			"message": map[string]interface{}{
				"token": token,
				"notification": map[string]string{
					"title": title,
					"body":  body,
				},
				"data": data,
			},
		}
		bodyBytes, err := json.Marshal(payload)
		if err != nil {
			log.Printf("notifications: marshal: %v", err)
			continue
		}
		req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(bodyBytes))
		if err != nil {
			log.Printf("notifications: new request: %v", err)
			continue
		}
		req.Header.Set("Authorization", "Bearer "+accessToken)
		req.Header.Set("Content-Type", "application/json")
		resp, err := httpClient.Do(req)
		if err != nil {
			log.Printf("notifications: send: %v", err)
			continue
		}
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			log.Printf("notifications: FCM v1 returned %d for token (len=%d)", resp.StatusCode, len(token))
		}
	}
}

// SendToUser sends a push notification to all devices of the given user.
func SendToUser(userID int, title, body string, data map[string]string) {
	if data == nil {
		data = make(map[string]string)
	}
	data["type"] = getOrEmpty(data, "type")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	tokens, err := getTokensForUser(ctx, userID)
	if err != nil || len(tokens) == 0 {
		return
	}
	sendToTokens(tokens, title, body, data)
}

// SendToUsers sends a push notification to all devices of the given users (e.g. admin broadcast).
func SendToUsers(userIDs []int, title, body string, data map[string]string) {
	if len(userIDs) == 0 {
		return
	}
	if data == nil {
		data = make(map[string]string)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	var allTokens []string
	for _, uid := range userIDs {
		tokens, err := getTokensForUser(ctx, uid)
		if err != nil {
			continue
		}
		allTokens = append(allTokens, tokens...)
	}
	if len(allTokens) == 0 {
		return
	}
	sendToTokens(allTokens, title, body, data)
}

// GetCustomerUserIDsWithTokens returns all user_ids that have role=customer and at least one FCM token.
func GetCustomerUserIDsWithTokens(ctx context.Context) ([]int, error) {
	rows, err := database.DB.Query(ctx,
		`SELECT DISTINCT f.user_id FROM fcm_tokens f
		 INNER JOIN users u ON u.id = f.user_id AND u.role = 'customer'
		 WHERE f.fcm_token != ''`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			continue
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// haversineKm returns distance in km between two points (lat/long in degrees).
func haversineKm(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371 // Earth radius in km
	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return R * c
}

// NotifyCustomersNewShopNearby finds customers within radiusKm of (shopLat, shopLong) and sends a push.
func NotifyCustomersNewShopNearby(shopLat, shopLong float64, shopName string) {
	initFCM()
	if projectID == "" || creds == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	rows, err := database.DB.Query(ctx,
		`SELECT id, lat, long FROM users WHERE role = 'customer' AND lat IS NOT NULL AND long IS NOT NULL`)
	if err != nil {
		log.Printf("notifications: new shop nearby query: %v", err)
		return
	}
	defer rows.Close()
	var userIDs []int
	for rows.Next() {
		var id int
		var lat, long *float64
		if err := rows.Scan(&id, &lat, &long); err != nil || lat == nil || long == nil {
			continue
		}
		dist := haversineKm(shopLat, shopLong, *lat, *long)
		if dist <= radiusKm {
			userIDs = append(userIDs, id)
		}
	}
	if len(userIDs) == 0 {
		return
	}
	title := "New print shop nearby"
	body := fmt.Sprintf("%s is now available for printing near you.", shopName)
	if body == " is now available for printing near you." {
		body = "A new print shop is now available near you."
	}
	data := map[string]string{"type": "new_shop_nearby"}
	SendToUsers(userIDs, title, body, data)
}

func getOrEmpty(m map[string]string, k string) string {
	if m == nil {
		return ""
	}
	return m[k]
}

// FormatAmount returns a short amount string for notifications (e.g. "₹50").
func FormatAmount(amount float64) string {
	return "₹" + strconv.FormatFloat(amount, 'f', 0, 64)
}
