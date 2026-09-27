package payment

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"time"
)

// RazorpayClient handles Razorpay API interactions
type RazorpayClient struct {
	KeyID     string
	KeySecret string
	BaseURL   string
	Client    *http.Client
}

// NewRazorpayClient creates a new Razorpay client
func NewRazorpayClient() (*RazorpayClient, error) {
	keyID := os.Getenv("RAZORPAY_KEY_ID")
	keySecret := os.Getenv("RAZORPAY_KEY_SECRET")

	if keyID == "" || keySecret == "" {
		return nil, fmt.Errorf("RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET must be set")
	}

	baseURL := "https://api.razorpay.com/v1"
	if os.Getenv("RAZORPAY_ENV") == "test" {
		baseURL = "https://api.razorpay.com/v1" // Same URL for test and live
	}

	return &RazorpayClient{
		KeyID:     keyID,
		KeySecret: keySecret,
		BaseURL:   baseURL,
		Client:    &http.Client{Timeout: 30 * time.Second},
	}, nil
}

// OrderRequest represents Razorpay order creation request
type OrderRequest struct {
	Amount   int64  `json:"amount"`   // Amount in paise
	Currency string `json:"currency"`
	Receipt string  `json:"receipt,omitempty"`
	Notes   map[string]string `json:"notes,omitempty"`
}

// OrderResponse represents Razorpay order response
type OrderResponse struct {
	ID        string `json:"id"`
	Entity    string `json:"entity"`
	Amount    int64  `json:"amount"`
	Currency  string `json:"currency"`
	Status    string `json:"status"`
	Receipt   string `json:"receipt"`
	CreatedAt int64  `json:"created_at"`
}

// CreateOrder creates a Razorpay order
func (c *RazorpayClient) CreateOrder(amount float64, receipt string, notes map[string]string) (*OrderResponse, error) {
	// Convert amount to paise (multiply by 100)
	amountPaise := int64(amount * 100)

	orderReq := OrderRequest{
		Amount:   amountPaise,
		Currency: "INR",
		Receipt:  receipt,
		Notes:    notes,
	}

	jsonData, err := json.Marshal(orderReq)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal order request: %w", err)
	}

	req, err := http.NewRequest("POST", c.BaseURL+"/orders", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.SetBasicAuth(c.KeyID, c.KeySecret)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.Client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("razorpay API error: %s (status: %d)", string(body), resp.StatusCode)
	}

	var orderResp OrderResponse
	if err := json.Unmarshal(body, &orderResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return &orderResp, nil
}

// PaymentResponse represents Razorpay payment response
type PaymentResponse struct {
	ID        string `json:"id"`
	Entity    string `json:"entity"`
	Amount    int64  `json:"amount"`
	Currency  string `json:"currency"`
	Status    string `json:"status"`
	OrderID   string `json:"order_id"`
	CreatedAt int64  `json:"created_at"`
}

// VerifyPayment verifies a payment by fetching it from Razorpay
func (c *RazorpayClient) VerifyPayment(paymentID string) (*PaymentResponse, error) {
	req, err := http.NewRequest("GET", c.BaseURL+"/payments/"+paymentID, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.SetBasicAuth(c.KeyID, c.KeySecret)

	resp, err := c.Client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("razorpay API error: %s (status: %d)", string(body), resp.StatusCode)
	}

	var paymentResp PaymentResponse
	if err := json.Unmarshal(body, &paymentResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return &paymentResp, nil
}

// VerifyWebhookSignature verifies Razorpay webhook signature
func (c *RazorpayClient) VerifyWebhookSignature(payload string, signature string) bool {
	webhookSecret := os.Getenv("RAZORPAY_WEBHOOK_SECRET")
	if webhookSecret == "" {
		return false
	}

	mac := hmac.New(sha256.New, []byte(webhookSecret))
	mac.Write([]byte(payload))
	expectedSignature := hex.EncodeToString(mac.Sum(nil))

	return hmac.Equal([]byte(signature), []byte(expectedSignature))
}

// RefundRequest represents a refund request
type RefundRequest struct {
	Amount int64  `json:"amount,omitempty"` // Amount in paise, omit for full refund
	Speed  string `json:"speed,omitempty"` // 'normal' or 'optimum'
	Notes  map[string]string `json:"notes,omitempty"`
}

// RefundResponse represents a refund response
type RefundResponse struct {
	ID        string `json:"id"`
	Entity    string `json:"entity"`
	Amount    int64  `json:"amount"`
	Currency  string `json:"currency"`
	PaymentID string `json:"payment_id"`
	Status    string `json:"status"`
	CreatedAt int64  `json:"created_at"`
}

// CreateRefund creates a refund for a payment
func (c *RazorpayClient) CreateRefund(paymentID string, amount *float64, notes map[string]string) (*RefundResponse, error) {
	refundReq := RefundRequest{
		Speed: "normal",
		Notes: notes,
	}

	if amount != nil {
		refundReq.Amount = int64(*amount * 100) // Convert to paise
	}

	jsonData, err := json.Marshal(refundReq)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal refund request: %w", err)
	}

	req, err := http.NewRequest("POST", c.BaseURL+"/payments/"+paymentID+"/refund", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.SetBasicAuth(c.KeyID, c.KeySecret)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.Client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("razorpay API error: %s (status: %d)", string(body), resp.StatusCode)
	}

	var refundResp RefundResponse
	if err := json.Unmarshal(body, &refundResp); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	return &refundResp, nil
}

// CalculateShopkeeperAmount calculates the amount to be paid to shopkeeper
// after deducting platform commission
func CalculateShopkeeperAmount(totalAmount float64, commissionPercent float64) float64 {
	if commissionPercent < 0 || commissionPercent > 1 {
		commissionPercent = 0 // Default to 0 if invalid
	}
	commission := totalAmount * commissionPercent
	return totalAmount - commission
}

// FormatAmount converts float64 to paise (int64)
func FormatAmount(amount float64) int64 {
	return int64(amount * 100)
}

// ParseAmount converts paise (int64) to float64
func ParseAmount(amountPaise int64) float64 {
	return float64(amountPaise) / 100.0
}

// GenerateReceipt generates a unique receipt ID for Razorpay order
func GenerateReceipt(userID int, timestamp int64) string {
	return fmt.Sprintf("qprint_%d_%d", userID, timestamp)
}

// GetExpiryTime returns the expiry time for payment (default 30 minutes)
func GetExpiryTime() time.Time {
	expiryMinutes := 30
	if envExpiry := os.Getenv("PAYMENT_LINK_EXPIRY_MINUTES"); envExpiry != "" {
		if minutes, err := strconv.Atoi(envExpiry); err == nil && minutes > 0 {
			expiryMinutes = minutes
		}
	}
	return time.Now().Add(time.Duration(expiryMinutes) * time.Minute)
}
