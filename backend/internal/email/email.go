package email

import (
	"fmt"
	"log"
	"net/smtp"
	"os"
	"strings"
)

type EmailService struct {
	smtpHost     string
	smtpPort     string
	smtpUser     string
	smtpPassword string
	fromEmail    string
	fromName     string
	enabled      bool
}

var service *EmailService

func Init() {
	// Check if Resend API key is set (preferred, works on Render free tier)
	resendAPIKey := os.Getenv("RESEND_API_KEY")
	if resendAPIKey == "" {
		// Fallback: try SMTP_PASSWORD as API key (for compatibility)
		resendAPIKey = os.Getenv("SMTP_PASSWORD")
	}

	// If API key exists, use Resend API instead of SMTP
	if resendAPIKey != "" {
		fromEmail := getEnvOrDefault("FROM_EMAIL", "onboarding@resend.dev")
		fromName := getEnvOrDefault("FROM_NAME", "Qprint")
		log.Printf("Email service initialized - Resend API (works on free tier), From: %s <%s>", fromName, fromEmail)
		// Set service to use API mode
		service = &EmailService{
			enabled: true, // Will use API mode
		}
		return
	}

	// Otherwise, use SMTP (requires paid Render plan)
	service = &EmailService{
		smtpHost:     os.Getenv("SMTP_HOST"),
		smtpPort:     getEnvOrDefault("SMTP_PORT", "587"),
		smtpUser:     os.Getenv("SMTP_USER"),
		smtpPassword: os.Getenv("SMTP_PASSWORD"),
		fromEmail:    getEnvOrDefault("FROM_EMAIL", os.Getenv("SMTP_USER")),
		fromName:     getEnvOrDefault("FROM_NAME", "Qprint"),
		enabled:      os.Getenv("SMTP_HOST") != "" && os.Getenv("SMTP_USER") != "" && os.Getenv("SMTP_PASSWORD") != "",
	}

	if !service.enabled {
		log.Println("Email service disabled - SMTP not configured. Emails will be logged to console.")
		log.Println("To enable email, set RESEND_API_KEY (works on free tier) or SMTP_HOST/SMTP_USER/SMTP_PASSWORD environment variables")
	} else {
		log.Printf("Email service initialized - SMTP: %s:%s, From: %s <%s>", service.smtpHost, service.smtpPort, service.fromName, service.fromEmail)
	}
}

func getEnvOrDefault(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

func SendPasswordResetEmail(to, token string) error {
	frontendURL := getEnvOrDefault("FRONTEND_URL", "http://localhost:3000")
	resetURL := fmt.Sprintf("%s/reset-password?token=%s", frontendURL, token)
	
	subject := "Reset Your Qprint Password"
	body := fmt.Sprintf(`
Hello,

You requested to reset your password for your Qprint account.

Click the link below to reset your password:
%s

This link will expire in 1 hour.

If you did not request this password reset, please ignore this email.

Best regards,
Qprint Team
`, resetURL)

	return sendEmail(to, subject, body)
}

func SendUsernameRecoveryEmail(to, username string) error {
	subject := "Your Qprint Username"
	body := fmt.Sprintf(`
Hello,

You requested to recover your username for your Qprint account.

Your username is: %s

You can use this username to log in to your account.

If you did not request this username recovery, please ignore this email.

Best regards,
Qprint Team
`, username)

	return sendEmail(to, subject, body)
}

// SendLoginOTPEmail sends a 6-digit one-time code for admin login.
func SendLoginOTPEmail(to, code string) error {
	subject := "Your Qprint Admin Login Code"
	body := fmt.Sprintf(`
Hello,

Your one-time login code for Qprint Admin is:

  %s

This code expires in 10 minutes. Do not share it with anyone.

If you did not request this code, please ignore this email and secure your account.

Best regards,
Qprint Team
`, code)

	return sendEmail(to, subject, body)
}

// SendSignupOTPEmail sends a 6-digit one-time code for sign-up email verification.
func SendSignupOTPEmail(to, code string) error {
	subject := "Your Qprint Sign-up Code"
	body := fmt.Sprintf(`
Hello,

Your sign-up verification code for Qprint is:

  %s

This code is valid for 10 minutes. Do not share it with anyone.

If you did not try to create an account, please ignore this email.

Best regards,
Qprint Team
`, code)

	return sendEmail(to, subject, body)
}

// SendReferralInviteEmail sends an invite email with the referrer's link (Resend or SMTP as configured).
func SendReferralInviteEmail(to, referrerName, referralLink string) error {
	subject := "You're invited to try Qprint"
	if referrerName != "" {
		subject = referrerName + " invited you to try Qprint"
	}
	body := fmt.Sprintf(`
Hi,

%s has invited you to try Qprint — print documents easily at nearby shops.

Sign up using this link to get a welcome bonus:
%s

Create your account, complete your first print or add money to your wallet, and you'll both earn rewards.

Best,
Qprint Team
`, referrerName, referralLink)
	return sendEmail(to, subject, body)
}

func sendEmail(to, subject, body string) error {
	// Check if Resend API is available (works on Render free tier)
	resendAPIKey := os.Getenv("RESEND_API_KEY")
	if resendAPIKey == "" {
		resendAPIKey = os.Getenv("SMTP_PASSWORD") // Fallback: use SMTP_PASSWORD as API key
	}

	if resendAPIKey != "" {
		// Use Resend API (works on free tier, no SMTP ports needed)
		return SendEmailViaAPI(to, subject, body)
	}

	// Fallback to SMTP (requires paid Render plan)
	if !service.enabled {
		// Development mode: log to console
		log.Println("=" + strings.Repeat("=", 78) + "=")
		log.Printf("EMAIL (Development Mode - Email not configured)")
		log.Println("=" + strings.Repeat("=", 78) + "=")
		log.Printf("To: %s", to)
		log.Printf("Subject: %s", subject)
		log.Printf("Body:\n%s", body)
		log.Println("=" + strings.Repeat("=", 78) + "=")
		return nil
	}

	// Production mode: send via SMTP
	auth := smtp.PlainAuth("", service.smtpUser, service.smtpPassword, service.smtpHost)
	
	msg := []byte(fmt.Sprintf("From: %s <%s>\r\n", service.fromName, service.fromEmail) +
		fmt.Sprintf("To: %s\r\n", to) +
		fmt.Sprintf("Subject: %s\r\n", subject) +
		"Content-Type: text/plain; charset=UTF-8\r\n" +
		"\r\n" +
		body + "\r\n")

	addr := fmt.Sprintf("%s:%s", service.smtpHost, service.smtpPort)
	err := smtp.SendMail(addr, auth, service.fromEmail, []string{to}, msg)
	
	if err != nil {
		log.Printf("Failed to send email to %s: %v", to, err)
		return err
	}
	
	log.Printf("Email sent successfully to %s", to)
	return nil
}
