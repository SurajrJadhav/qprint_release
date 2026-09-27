package admin

import (
	"net/http"
	"os"
	"strings"
)

// clientIP returns the client IP from X-Forwarded-For (first element) or RemoteAddr.
// On Render, X-Forwarded-For is set by the proxy.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if i := strings.Index(xff, ","); i > 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	addr := r.RemoteAddr
	if i := strings.LastIndex(addr, ":"); i >= 0 {
		addr = addr[:i]
	}
	return addr
}

// parseAllowedAdminIPs returns a set of allowed IPs from ALLOWED_ADMIN_IPS (comma-separated).
// If empty, returns nil (no whitelist enforced).
func parseAllowedAdminIPs() map[string]struct{} {
	s := os.Getenv("ALLOWED_ADMIN_IPS")
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	set := make(map[string]struct{}, len(parts))
	for _, p := range parts {
		ip := strings.TrimSpace(p)
		if ip != "" {
			set[ip] = struct{}{}
		}
	}
	if len(set) == 0 {
		return nil
	}
	return set
}

// AdminIPWhitelist returns a middleware that restricts /admin/* to IPs in ALLOWED_ADMIN_IPS.
// If ALLOWED_ADMIN_IPS is not set or empty, all IPs are allowed (current behavior).
// Set ALLOWED_ADMIN_IPS on Render to e.g. your office IP or VPN IP for extra security.
func AdminIPWhitelist(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ips := parseAllowedAdminIPs()
		if ips == nil {
			next.ServeHTTP(w, r)
			return
		}
		ip := clientIP(r)
		if _, ok := ips[ip]; ok {
			next.ServeHTTP(w, r)
			return
		}
		http.Error(w, "Forbidden", http.StatusForbidden)
	})
}
