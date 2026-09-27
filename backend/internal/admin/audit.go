package admin

import (
	"log"
	"time"
)

// LogAdmin writes a structured audit log line for admin actions.
// Format: AUDIT timestamp=... admin_id=... action=... target=... details=...
// Render (and most hosts) capture stdout; use log so it appears in Render logs.
func LogAdmin(adminID int, action, target, details string) {
	log.Printf("AUDIT timestamp=%s admin_id=%d action=%s target=%s details=%s",
		time.Now().UTC().Format(time.RFC3339), adminID, action, target, details)
}
