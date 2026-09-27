package shopkeeperstream

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sync"
	"time"
)

const (
	eventNewOrder = "new_order"
	heartbeatSec  = 30
	chanBufSize   = 8
	// maxConnectionsPerShop bounds concurrent SSE connections per shopkeeper
	maxConnectionsPerShop = 16
)

var (
	mu      sync.Mutex
	registry = make(map[int][]chan []byte) // shopID -> list of event channels
)

// Register adds a connection for the given shop and returns the channel and an unregister function.
func Register(shopID int) (ch chan []byte, unregister func()) {
	ch = make(chan []byte, chanBufSize)
	mu.Lock()
	conns := registry[shopID]
	if len(conns) >= maxConnectionsPerShop {
		// Drop the oldest connection reference to avoid unbounded growth.
		conns = conns[1:]
	}
	conns = append(conns, ch)
	registry[shopID] = conns
	mu.Unlock()
	unregister = func() {
		mu.Lock()
		defer mu.Unlock()
		list := registry[shopID]
		for i, c := range list {
			if c == ch {
				registry[shopID] = append(list[:i], list[i+1:]...)
				break
			}
		}
		if len(registry[shopID]) == 0 {
			delete(registry, shopID)
		}
		// Do not close(ch): Notify may be sending to it concurrently; leave for GC.
	}
	return ch, unregister
}

// NotifyShopNewQueueJob sends a new_order SSE event to all connected shopkeeper clients for the shop.
// Call this when one or more files are added to the shop's queue (e.g. after upload).
func NotifyShopNewQueueJob(shopID int, fileCount int) {
	payload, _ := json.Marshal(map[string]interface{}{
		"event":       eventNewOrder,
		"file_count": fileCount,
		"message":    fmt.Sprintf("New print job: %d file(s) in queue", fileCount),
	})
	msg := formatSSE("new_order", string(payload))

	mu.Lock()
	conns := make([]chan []byte, len(registry[shopID]))
	copy(conns, registry[shopID])
	mu.Unlock()

	for _, ch := range conns {
		select {
		case ch <- msg:
		default:
			// channel full or closed; skip
		}
	}
}

func formatSSE(event, data string) []byte {
	return []byte("event: " + event + "\ndata: " + data + "\n\n")
}

// Serve runs the SSE stream for the given shopID. It blocks until the client disconnects or context is done.
// The caller must have already set the response writer and validated that the user is a shopkeeper for this shop.
func Serve(w http.ResponseWriter, r *http.Request, shopID int) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	ch, unregister := Register(shopID)
	defer unregister()

	ctx := r.Context()
	heartbeat := time.NewTicker(heartbeatSec * time.Second)
	defer heartbeat.Stop()

	for {
		select {
		case msg, ok := <-ch:
			if !ok {
				return
			}
			if _, err := w.Write(msg); err != nil {
				return
			}
			flusher.Flush()
		case <-heartbeat.C:
			if _, err := w.Write(formatSSE("heartbeat", "{}")); err != nil {
				return
			}
			flusher.Flush()
		case <-ctx.Done():
			return
		}
	}
}
