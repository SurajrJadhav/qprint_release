package main

import (
	"backend/internal/database"
	"context"
	"fmt"
	"log"

	"github.com/joho/godotenv"
)

func main() {
	// Load environment variables
	if err := godotenv.Load(".env"); err != nil {
		if err := godotenv.Load("../.env"); err != nil {
			if err := godotenv.Load("../../.env"); err != nil {
				log.Println("No .env file found, using environment variables")
			}
		}
	}

	database.Connect()
	defer database.Close()

	fmt.Println("Checking users in database...")
	fmt.Println()

	var totalUsers, adminUsers, customerUsers, shopkeeperUsers int

	// Get total users
	err := database.DB.QueryRow(context.Background(), "SELECT COUNT(*) FROM users").Scan(&totalUsers)
	if err != nil {
		log.Fatalf("Failed to get total users: %v", err)
	}

	// Get admin users
	err = database.DB.QueryRow(context.Background(), "SELECT COUNT(*) FROM users WHERE role = 'admin'").Scan(&adminUsers)
	if err != nil {
		log.Fatalf("Failed to get admin users: %v", err)
	}

	// Get customer users
	err = database.DB.QueryRow(context.Background(), "SELECT COUNT(*) FROM users WHERE role = 'customer'").Scan(&customerUsers)
	if err != nil {
		log.Fatalf("Failed to get customer users: %v", err)
	}

	// Get shopkeeper users
	err = database.DB.QueryRow(context.Background(), "SELECT COUNT(*) FROM users WHERE role = 'shopkeeper'").Scan(&shopkeeperUsers)
	if err != nil {
		log.Fatalf("Failed to get shopkeeper users: %v", err)
	}

	fmt.Printf("Total Users:     %d\n", totalUsers)
	fmt.Printf("  - Admins:     %d\n", adminUsers)
	fmt.Printf("  - Customers:  %d\n", customerUsers)
	fmt.Printf("  - Shopkeepers: %d\n", shopkeeperUsers)
	fmt.Println()

	if totalUsers == 0 {
		fmt.Println("⚠ No users found in database!")
		fmt.Println()
		fmt.Println("To create users:")
		fmt.Println("  1. Register at http://localhost:3000/register")
		fmt.Println("  2. Or create admin: manage.bat admin <username> <password>")
		return
	}

	// List all users
	fmt.Println("All Users:")
	fmt.Println("----------")
	rows, err := database.DB.Query(context.Background(),
		"SELECT id, username, role, email, created_at FROM users ORDER BY created_at DESC")
	if err != nil {
		log.Fatalf("Failed to query users: %v", err)
	}
	defer rows.Close()

	for rows.Next() {
		var id int
		var username, role string
		var email *string
		var createdAt string

		err := rows.Scan(&id, &username, &role, &email, &createdAt)
		if err != nil {
			log.Printf("Failed to scan user: %v", err)
			continue
		}

		emailStr := "N/A"
		if email != nil {
			emailStr = *email
		}

		fmt.Printf("ID: %d | Username: %s | Role: %s | Email: %s\n", id, username, role, emailStr)
	}

	fmt.Println()
	fmt.Println("✅ Users found! They should appear in admin panel.")
}
