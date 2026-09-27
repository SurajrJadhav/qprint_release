package shopstatus

import (
	"backend/internal/database"
	"context"
	"log"
	"os"
	"strconv"
	"time"
)

func envInt(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		return def
	}
	return n
}

// StartSweeper periodically auto-closes shops when both:
// - app heartbeat is stale, and
// - web activity is stale.
//
// Defaults:
// - interval: 60s
// - app timeout: 12 minutes
// - web timeout: 25 minutes
//
// Configurable via env:
// - SHOP_SWEEPER_INTERVAL_SECONDS
// - SHOP_APP_HEARTBEAT_TIMEOUT_MINUTES
// - SHOP_WEB_ACTIVITY_TIMEOUT_MINUTES
func StartSweeper(ctx context.Context) {
	intervalSeconds := envInt("SHOP_SWEEPER_INTERVAL_SECONDS", 60)
	appTimeoutMin := envInt("SHOP_APP_HEARTBEAT_TIMEOUT_MINUTES", 12)
	webTimeoutMin := envInt("SHOP_WEB_ACTIVITY_TIMEOUT_MINUTES", 25)

	ticker := time.NewTicker(time.Duration(intervalSeconds) * time.Second)
	go func() {
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				// Close shops only when BOTH sources are stale.
				// - If app heartbeat is recent, do not close due to web inactivity.
				// - If web activity is recent, do not close due to app inactivity (useful if web is allowed to keep open).
				_, err := database.DB.Exec(context.Background(),
					`UPDATE users
					 SET is_open = FALSE
					 WHERE role = 'shopkeeper'
					   AND is_open = TRUE
					   AND (last_app_heartbeat_at IS NULL OR last_app_heartbeat_at < NOW() - make_interval(mins => $1))
					   AND (last_web_activity_at IS NULL OR last_web_activity_at < NOW() - make_interval(mins => $2))`,
					appTimeoutMin, webTimeoutMin)
				if err != nil {
					log.Printf("shopstatus sweeper: %v", err)
				}
			}
		}
	}()
}

