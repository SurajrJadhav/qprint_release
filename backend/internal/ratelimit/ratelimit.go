package ratelimit

import (
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// Limiter is a simple per-key (e.g. IP) rate limiter with a fixed window.
type Limiter struct {
	mu       sync.Mutex
	entries  map[string]*window
	limit    int
	window   time.Duration
	cleanup  time.Time
}

type window struct {
	count int
	start time.Time
}

// NewLimiter returns a limiter that allows limit requests per window per key.
func NewLimiter(limit int, windowDur time.Duration) *Limiter {
	return &Limiter{
		entries: make(map[string]*window),
		limit:   limit,
		window:  windowDur,
		cleanup: time.Now().Add(windowDur * 2),
	}
}

// Allow reports whether the key (e.g. IP) is allowed. It updates the window.
func (l *Limiter) Allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	if now.After(l.cleanup) {
		l.entries = make(map[string]*window)
		l.cleanup = now.Add(l.window * 2)
	}
	w, ok := l.entries[key]
	if !ok || now.Sub(w.start) >= l.window {
		l.entries[key] = &window{count: 1, start: now}
		return true
	}
	if w.count >= l.limit {
		return false
	}
	w.count++
	return true
}

// KeyFromRequest returns the client IP for rate limiting.
// When TRUST_PROXY_HEADERS=true (e.g. behind Cloudflare or a trusted reverse proxy),
// uses CF-Connecting-IP then X-Forwarded-For. Otherwise uses only RemoteAddr to avoid
// spoofing (attacker could forge X-Forwarded-For to bypass or abuse rate limits).
func KeyFromRequest(r *http.Request) string {
	if os.Getenv("TRUST_PROXY_HEADERS") != "true" {
		addr := r.RemoteAddr
		if i := strings.LastIndex(addr, ":"); i >= 0 {
			addr = addr[:i]
		}
		return addr
	}
	// Cloudflare provides the real client IP in CF-Connecting-IP
	if cfIP := r.Header.Get("CF-Connecting-IP"); cfIP != "" {
		return strings.TrimSpace(cfIP)
	}
	// Standard proxy header (only when trusted)
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		for i := 0; i < len(xff); i++ {
			if xff[i] == ',' {
				return strings.TrimSpace(xff[:i])
			}
		}
		return strings.TrimSpace(xff)
	}
	addr := r.RemoteAddr
	if i := strings.LastIndex(addr, ":"); i >= 0 {
		addr = addr[:i]
	}
	return addr
}

// Middleware returns a handler that rate-limits by IP and returns 429 when exceeded.
func Middleware(limit int, window time.Duration) func(http.Handler) http.Handler {
	lim := NewLimiter(limit, window)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := KeyFromRequest(r)
			if !lim.Allow(key) {
				http.Error(w, "Too many requests. Please try again later.", http.StatusTooManyRequests)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// PathPrefixMiddleware returns a handler that rate-limits by IP only when the request path
// has the given prefix (e.g. "/file/" to protect file-by-code endpoints from brute-force).
func PathPrefixMiddleware(pathPrefix string, limit int, window time.Duration) func(http.Handler) http.Handler {
	lim := NewLimiter(limit, window)
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if pathPrefix != "" && strings.HasPrefix(r.URL.Path, pathPrefix) {
				key := KeyFromRequest(r)
				if !lim.Allow(key) {
					http.Error(w, "Too many requests. Please try again later.", http.StatusTooManyRequests)
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

// PathsMiddleware returns a handler that rate-limits by IP only when the request path
// is exactly one of the given paths (e.g. stricter limit for OTP verify endpoints).
func PathsMiddleware(paths []string, limit int, window time.Duration) func(http.Handler) http.Handler {
	lim := NewLimiter(limit, window)
	set := make(map[string]struct{}, len(paths))
	for _, p := range paths {
		set[p] = struct{}{}
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if _, ok := set[r.URL.Path]; ok {
				key := KeyFromRequest(r)
				if !lim.Allow(key) {
					http.Error(w, "Too many requests. Please try again later.", http.StatusTooManyRequests)
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}
