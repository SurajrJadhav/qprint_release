package email

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
)

// SendEmailViaAPI sends email using Resend REST API via HTTP (no external SDK needed)
func SendEmailViaAPI(to, subject, body string) error {
	apiKey := os.Getenv("RESEND_API_KEY")
	if apiKey == "" {
		// Fallback: try SMTP_PASSWORD as API key (for compatibility)
		apiKey = os.Getenv("SMTP_PASSWORD")
	}

	if apiKey == "" {
		// Development mode: log to console
		log.Println("=" + strings.Repeat("=", 78) + "=")
		log.Printf("EMAIL (Development Mode - RESEND_API_KEY not configured)")
		log.Println("=" + strings.Repeat("=", 78) + "=")
		log.Printf("To: %s", to)
		log.Printf("Subject: %s", subject)
		log.Printf("Body:\n%s", body)
		log.Println("=" + strings.Repeat("=", 78) + "=")
		return nil
	}

	fromEmail := getEnvOrDefault("FROM_EMAIL", "onboarding@resend.dev")
	fromName := getEnvOrDefault("FROM_NAME", "Qprint")
	fromAddress := fmt.Sprintf("%s <%s>", fromName, fromEmail)

	// Resend API request payload
	payload := map[string]interface{}{
		"from":    fromAddress,
		"to":      []string{to},
		"subject": subject,
		"text":    body,
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		log.Printf("Failed to marshal email payload: %v", err)
		return err
	}

	// Create HTTP request to Resend API
	req, err := http.NewRequest("POST", "https://api.resend.com/emails", bytes.NewBuffer(jsonData))
	if err != nil {
		log.Printf("Failed to create HTTP request: %v", err)
		return err
	}

	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", apiKey))
	req.Header.Set("Content-Type", "application/json")

	// Send request
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("Failed to send email via Resend API to %s: %v", to, err)
		return err
	}
	defer resp.Body.Close()

	// Check response
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var errorBody bytes.Buffer
		errorBody.ReadFrom(resp.Body)
		log.Printf("Failed to send email via Resend API to %s: HTTP %d - %s", to, resp.StatusCode, errorBody.String())
		return fmt.Errorf("resend API error: HTTP %d", resp.StatusCode)
	}

	// Parse response to get email ID
	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err == nil {
		if id, ok := result["id"].(string); ok {
			log.Printf("Email sent successfully via Resend API to %s (ID: %s)", to, id)
		} else {
			log.Printf("Email sent successfully via Resend API to %s", to)
		}
	} else {
		log.Printf("Email sent successfully via Resend API to %s", to)
	}

	return nil
}
