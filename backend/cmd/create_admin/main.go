package main

import (
	"backend/internal/auth"
	"backend/internal/database"
	"context"
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

func generateInternalUsername(ctx context.Context) string {
	for i := 0; i < 20; i++ {
		b := make([]byte, 8)
		if _, err := rand.Read(b); err != nil {
			continue
		}
		u := "u_" + hex.EncodeToString(b)
		var exists int
		if database.DB.QueryRow(ctx, "SELECT 1 FROM users WHERE username = $1 LIMIT 1", u).Scan(&exists) != nil {
			return u
		}
	}
	return "u_" + fmt.Sprintf("%x", time.Now().UnixNano())
}

func main() {
	if err := godotenv.Load(".env"); err != nil {
		if err := godotenv.Load("../.env"); err != nil {
			if err := godotenv.Load("../../.env"); err != nil {
				log.Println("No .env file found, using environment variables")
			}
		}
	}

	password := flag.String("password", "", "Admin password (required)")
	email := flag.String("email", "", "Admin email (required)")
	fullName := flag.String("name", "", "Admin full name (optional)")
	flag.Parse()

	if *password == "" || strings.TrimSpace(*email) == "" {
		fmt.Println("Error: email and password are required")
		fmt.Println()
		fmt.Println("Usage:")
		fmt.Println("  go run cmd/create_admin/main.go -email <email> -password <password> [-name \"Admin User\"]")
		os.Exit(1)
	}

	database.Connect()
	defer database.Close()

	ctx := context.Background()
	emailValue := strings.TrimSpace(strings.ToLower(*email))

	var existingEmailID int
	if database.DB.QueryRow(ctx, "SELECT id FROM users WHERE LOWER(TRIM(email)) = $1", emailValue).Scan(&existingEmailID) == nil {
		fmt.Printf("Error: Email '%s' already exists (ID: %d)\n", emailValue, existingEmailID)
		os.Exit(1)
	}

	hashedPassword, err := auth.HashPassword(*password)
	if err != nil {
		log.Fatalf("Failed to hash password: %v", err)
	}

	fullNameValue := strings.TrimSpace(*fullName)
	if fullNameValue == "" {
		fullNameValue = "Admin User"
	}

	internalUsername := generateInternalUsername(ctx)
	var userID int
	err = database.DB.QueryRow(ctx,
		"INSERT INTO users (username, password_hash, role, email, full_name) VALUES ($1, $2, $3, $4, $5) RETURNING id",
		internalUsername, hashedPassword, "admin", emailValue, fullNameValue).Scan(&userID)
	if err != nil {
		log.Fatalf("Failed to create admin: %v", err)
	}

	fmt.Println()
	fmt.Println("========================================")
	fmt.Println("  Admin Account Created Successfully")
	fmt.Println("========================================")
	fmt.Println()
	fmt.Printf("User ID:    %d\n", userID)
	fmt.Printf("Email:      %s\n", emailValue)
	fmt.Printf("Full Name:  %s\n", fullNameValue)
	fmt.Printf("Role:       admin\n")
	fmt.Println()
	fmt.Println("Login with this email at the admin panel (OTP or password).")
	fmt.Println()
}
