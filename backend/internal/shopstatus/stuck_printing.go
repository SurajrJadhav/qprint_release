package shopstatus

import (
	"backend/internal/database"
	"context"
	"log"
	"os"
	"strconv"
	"time"
)

// StartStuckPrintingSweeper reverts files in status 'printing' to 'uploaded' for shops
// whose last_app_heartbeat_at is older than SHOP_PRINTING_STALE_MINUTES (default 10).
// This handles the case when the shopkeeper app crashes during print: the app never
// calls confirm or print-failed, so backend would leave the order stuck in "printing".
// When heartbeats stop, we assume the app is gone and revert so the customer can
// withdraw or the shopkeeper can retry after reopening the app.
//
// Configurable via env: SHOP_PRINTING_STALE_MINUTES (default 10).
func StartStuckPrintingSweeper(ctx context.Context) {
	staleMin := envInt("SHOP_PRINTING_STALE_MINUTES", 10)
	intervalSeconds := envInt("SHOP_SWEEPER_INTERVAL_SECONDS", 60)
	if v := os.Getenv("SHOP_STUCK_PRINTING_INTERVAL_SECONDS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			intervalSeconds = n
		}
	}

	ticker := time.NewTicker(time.Duration(intervalSeconds) * time.Second)
	go func() {
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				result, err := database.DB.Exec(context.Background(),
					`UPDATE files f
					 SET status = 'uploaded'
					 FROM users u
					 WHERE f.shop_id = u.id
					   AND f.status = 'printing'
					   AND u.role = 'shopkeeper'
					   AND (u.last_app_heartbeat_at IS NULL OR u.last_app_heartbeat_at < NOW() - make_interval(mins => $1))`,
					staleMin)
				if err != nil {
					log.Printf("shopstatus stuck-printing sweeper: %v", err)
					continue
				}
				if n := result.RowsAffected(); n > 0 {
					log.Printf("shopstatus stuck-printing sweeper: reverted %d file(s) from printing to uploaded (shop heartbeat stale)", n)
				}
			}
		}
	}()
}
