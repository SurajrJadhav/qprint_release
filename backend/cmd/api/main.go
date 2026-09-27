package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"backend/internal/admin"
	"backend/internal/auth"
	"backend/internal/csrf"
	"backend/internal/database"
	"backend/internal/email"
	"backend/internal/handlers"
	"backend/internal/middleware"
	"backend/internal/ratelimit"
	"backend/internal/secureheaders"
	"backend/internal/shopstatus"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/joho/godotenv"
)

// parseAllowedOrigins splits ALLOWED_ORIGINS by comma and trims spaces. Returns nil if empty.
func parseAllowedOrigins(env string) []string {
	if env == "" {
		return nil
	}
	parts := strings.Split(env, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if s := strings.TrimSpace(p); s != "" {
			out = append(out, s)
		}
	}
	return out
}

func main() {
	// Force load .env file and OVERRIDE any existing environment variables
	if err := godotenv.Overload(".env"); err != nil {
		if err := godotenv.Overload("backend/.env"); err != nil {
			log.Println("No .env file found, using environment variables")
		} else {
			log.Println("Loaded and OVERRODE env vars from backend/.env")
		}
	} else {
		log.Println("Loaded and OVERRODE env vars from current directory")
	}

	database.Connect()
	database.InitSchema()
	defer database.Close()

	// Background auto-close for shop availability (heartbeat/inactivity)
	shopstatus.StartSweeper(context.Background())
	// Revert stuck "printing" orders when shop heartbeat is stale (e.g. app crashed during print)
	shopstatus.StartStuckPrintingSweeper(context.Background())

	// Validate JWT secret before accepting requests (fail fast if missing/weak)
	if err := auth.InitJWTSecret(); err != nil {
		log.Fatalf("JWT secret validation failed: %v", err)
	}

	// Initialize storage AFTER .env is loaded
	handlers.InitStorage()

	email.Init()

	// Production: forbid insecure options (fail fast)
	if os.Getenv("ENVIRONMENT") == "production" {
		if os.Getenv("SKIP_SIGNUP_OTP") == "true" {
			log.Fatal("SKIP_SIGNUP_OTP must not be true in production (email verification required)")
		}
		if os.Getenv("TEST_MODE") == "true" {
			log.Fatal("TEST_MODE must not be true in production (payment and validations must be enforced)")
		}
		if os.Getenv("ALLOWED_ADMIN_IPS") == "" {
			log.Println("WARNING: ALLOWED_ADMIN_IPS is not set. Admin API is reachable from any IP (protected by login + 2FA). Set ALLOWED_ADMIN_IPS to restrict by IP (e.g. office or VPN). See ADMIN_ACCESS_QUICK_START.md for options when your IP changes.")
		}
	}

	r := chi.NewRouter()
	r.Use(chimw.Logger)
	r.Use(chimw.Recoverer)
	r.Use(secureheaders.Middleware)

	// CORS: require explicit ALLOWED_ORIGINS in production (comma-separated). No wildcard with credentials.
	allowedOrigins := parseAllowedOrigins(os.Getenv("ALLOWED_ORIGINS"))
	if len(allowedOrigins) == 0 {
		if os.Getenv("ENVIRONMENT") == "development" || os.Getenv("TEST_MODE") == "true" {
			allowedOrigins = []string{"http://localhost:3000", "http://localhost:3001", "http://127.0.0.1:3000", "http://127.0.0.1:3001"}
			log.Println("CORS: using development defaults (set ALLOWED_ORIGINS in production)")
		} else {
			log.Fatal("ALLOWED_ORIGINS must be set in production (comma-separated list, e.g. https://app.example.com,https://admin.example.com). Do not use * with credentials.")
		}
	}
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   allowedOrigins,
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token", "X-Platform"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))
	// CSRF is not applied globally so GET /csrf-token can issue a token; applied per-group below.
	//
	// Rate limits (all per IP):
	//   - Auth group: 50 / 15 min (login, register, send-otp, forgot-password, reset-password, forgot-username)
	//   - /payment/webhook: 120 / min
	//   - /file/*: 60 / min (file-by-code download/status)
	//   - /upload: 30 / min
	//   - /create-payment-order: 30 / min
	//   - /wallet/topup: 30 / min

	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("Welcome to Qprint API - Print Without Standing in Queue"))
	})
	r.Get("/csrf-token", csrf.Handler)

	// Public page for Play Store "Delete data" link (required when app collects user data)
	r.Get("/delete-data", handlers.DeleteDataPage)

	// App download links (public — used by Download apps page)
	r.Get("/app-downloads", handlers.GetAppDownloads)

	// Shop QR redirect: /s/{id} — public, rate-limited; when scanned outside app, tries to open app then redirects to Play Store/website
	shopRedirectLimiter := ratelimit.PathPrefixMiddleware("/s/", 60, time.Minute)
	r.With(shopRedirectLimiter).Get("/s/{id}", handlers.ShopRedirectPage)

	// Auth endpoints: 50/15min per IP; stricter 10/15min for OTP verify endpoints (brute-force mitigation)
	authLimiter := ratelimit.Middleware(50, 15*time.Minute)
	verifyOTPStrictLimiter := ratelimit.PathsMiddleware(
		[]string{"/register/verify-otp", "/login/verify-otp", "/login/verify-2fa"},
		10, 15*time.Minute)
	authBodyLimit := middleware.MaxBytes(1 << 20) // 1MB for JSON auth payloads
	r.With(verifyOTPStrictLimiter, authLimiter, authBodyLimit, csrf.ValidateOptional).Group(func(r chi.Router) {
		r.Post("/register/send-otp", handlers.RegisterSendOTP)
		r.Post("/register/verify-otp", handlers.RegisterVerifyOTP)
		r.Post("/register", handlers.Register)
		r.Post("/login", handlers.Login)
		r.Post("/login/request-otp", handlers.LoginRequestOTP)
		r.Post("/login/verify-otp", handlers.LoginVerifyOTP)
		r.Post("/login/google", handlers.LoginGoogle)
		r.Post("/login/verify-2fa", handlers.Verify2FA)
		r.Post("/admin/login/request-otp", handlers.RequestAdminLoginOTP)
		r.Post("/admin/login/verify-otp", handlers.VerifyAdminLoginOTP)
		r.Post("/forgot-password", handlers.ForgotPassword)
		r.Post("/reset-password", handlers.ResetPassword)
	})

	// Payment webhook (public, but signature verified). Rate limit to reduce DoS / abuse (120/min per IP allows Razorpay retries).
	webhookLimiter := ratelimit.Middleware(120, time.Minute)
	r.With(webhookLimiter).Post("/payment/webhook", handlers.PaymentWebhook)

	// Protected routes (require auth + CSRF for state-changing requests)
	// Rate limits: file-by-code 60/min (brute-force mitigation), upload 30/min, payment creation/topup 30/min per IP
	fileCodeLimiter := ratelimit.PathPrefixMiddleware("/file/", 60, time.Minute)
	uploadLimiter := ratelimit.PathPrefixMiddleware("/upload", 30, time.Minute)
	createOrderLimiter := ratelimit.PathPrefixMiddleware("/create-payment-order", 30, time.Minute)
	walletTopupLimiter := ratelimit.PathPrefixMiddleware("/wallet/topup", 30, time.Minute)
	r.Group(func(r chi.Router) {
		r.Use(fileCodeLimiter)
		r.Use(uploadLimiter)
		r.Use(createOrderLimiter)
		r.Use(walletTopupLimiter)
		r.Use(auth.AuthMiddleware)
		r.Use(csrf.Validate)
		r.Use(middleware.ShopkeeperActivity)
		r.Post("/logout", handlers.Logout)
		// Payment routes
		r.Post("/calculate-cost", handlers.CalculateCost)
		r.Post("/calculate-cost-from-pages", handlers.CalculateCostFromPages)
		r.Post("/create-payment-order", handlers.CreatePaymentOrder)
		r.Get("/payment-order/{orderId}/status", handlers.GetPaymentStatus)
		r.Get("/shopkeeper/payouts", handlers.GetShopkeeperPayouts)
		// Wallet (customer)
		r.Get("/wallet/balance", handlers.GetWalletBalance)
		r.Get("/wallet/transactions", handlers.GetWalletTransactions)
		r.Post("/wallet/topup", handlers.TopupWallet)
		
		// File routes
		r.Post("/upload", handlers.UploadFile)
		r.Get("/file/{code}", handlers.DownloadFile)
		r.Post("/file/{code}/confirm", handlers.ConfirmPrivatePrint)
		r.Post("/file/{code}/print-started", handlers.PrintStartedPrivate)
		r.Post("/file/{code}/print-failed", handlers.PrintFailedPrivate)
		r.Get("/file/{code}/status", handlers.CheckFileStatus)
		r.Get("/shops", handlers.GetNearestShops)
		r.Get("/shops/{id}", handlers.GetShopByID)
		r.Get("/queue", handlers.GetShopQueue)
		r.Get("/queue/{orderGroupId}/files", handlers.GetOrderFiles)
		r.Get("/queue/download/{fileId}", handlers.DownloadQueueFile)
		r.Post("/queue/{fileId}/confirm", handlers.ConfirmQueuePrint)
		r.Post("/queue/{fileId}/print-started", handlers.PrintStartedQueue)
		r.Post("/queue/{fileId}/print-failed", handlers.PrintFailedQueue)
		r.Post("/queue/{fileId}/cancel", handlers.CancelOrderByShopkeeper)
		r.Get("/my-files", handlers.GetMyFiles)
		r.Get("/my-orders", handlers.GetMyOrders)
		r.Get("/shop/history", handlers.GetShopHistory)
		r.Get("/profile", handlers.GetProfile)
		r.Put("/profile", handlers.UpdateProfile)
		r.Delete("/profile", handlers.DeleteMyAccount)
		r.Get("/referral/summary", handlers.GetReferralSummary)
		r.Get("/referral/history", handlers.GetReferralHistory)
		r.Post("/referral/invite", handlers.ReferralInvite)
		r.Patch("/shopkeeper/pricing", handlers.UpdateShopPricing)
		r.Post("/shop/status", handlers.ToggleShopStatus)
		r.Post("/shop/heartbeat", handlers.ShopHeartbeat)
		r.Post("/withdraw/{fileId}", handlers.WithdrawPrint)
		r.Post("/notifications/register-token", handlers.RegisterFCMToken)
	})

	// Shopkeeper SSE stream (auth only; no CSRF for GET stream)
	r.Group(func(r chi.Router) {
		r.Use(auth.AuthMiddleware)
		r.Use(middleware.ShopkeeperActivity)
		r.Get("/shopkeeper/events", handlers.ShopkeeperEventsStream)
	})

	// Admin routes (optional IP whitelist via ALLOWED_ADMIN_IPS; middleware accepts cookie or Bearer)
	r.Group(func(r chi.Router) {
		r.Use(admin.AdminIPWhitelist)
		r.Use(admin.AdminMiddleware)
		r.Use(csrf.Validate)
		// Dashboard
		r.Get("/admin/me", admin.GetAdminMe)
		r.Put("/admin/me", admin.UpdateAdminMe)
		r.Get("/admin/dashboard/stats", admin.GetDashboardStats)
		
		// User management
		r.Get("/admin/users", admin.GetUsers)
		r.Get("/admin/users/details", admin.GetUserDetails)
		r.Post("/admin/users/delete", admin.DeleteAccount)
		
		// Order management
		r.Get("/admin/orders", admin.GetOrders)
		
		// Payout management
		r.Get("/admin/payouts", admin.GetPayouts)
		r.Put("/admin/payouts/update", admin.UpdatePayoutStatus)
		r.Put("/admin/payouts/bulk-update", admin.BulkUpdatePayouts)
		r.Get("/admin/payouts/export", admin.ExportPayouts)
		r.Put("/admin/app-downloads", admin.UpdateAppDownloads)
		r.Post("/admin/notifications/send", admin.SendNotificationToAllCustomers)
		// 2FA for admin
		r.Get("/admin/2fa/status", admin.TwoFAStatus)
		r.Post("/admin/2fa/enable", admin.TwoFAEnable)
		r.Post("/admin/2fa/disable", admin.TwoFADisable)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	addr := ":" + port
	certFile := os.Getenv("TLS_CERT_FILE")
	keyFile := os.Getenv("TLS_KEY_FILE")

	server := &http.Server{
		Addr:              addr,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
		// ReadTimeout includes body for non-streaming requests; keep conservative to avoid killing large uploads.
		ReadTimeout: 60 * time.Second,
		// WriteTimeout bounds slow clients; uploads/downloads should complete well within this at expected sizes.
		WriteTimeout: 120 * time.Second,
		IdleTimeout:  120 * time.Second,
		// 1MB header limit is plenty for typical cookies and prevents header abuse.
		MaxHeaderBytes: 1 << 20,
	}

	if certFile != "" && keyFile != "" {
		if _, err := os.Stat(certFile); err != nil {
			log.Fatalf("TLS_CERT_FILE not readable: %v", err)
		}
		if _, err := os.Stat(keyFile); err != nil {
			log.Fatalf("TLS_KEY_FILE not readable: %v", err)
		}
		fmt.Printf("Server running HTTPS on port %s\n", port)
		if err := server.ListenAndServeTLS(certFile, keyFile); err != nil {
			log.Fatalf("Failed to start HTTPS server: %v", err)
		}
	} else {
		fmt.Printf("Server running on port %s (HTTP). For HTTPS, set TLS_CERT_FILE and TLS_KEY_FILE.\n", port)
		if err := server.ListenAndServe(); err != nil {
			log.Fatalf("Failed to start server: %v", err)
		}
	}
}
