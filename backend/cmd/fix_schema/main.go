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

	fmt.Println("Checking and creating missing tables...")

	// Check if payment_orders exists
	var exists bool
	err := database.DB.QueryRow(context.Background(),
		"SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'payment_orders')").Scan(&exists)

	if err != nil {
		log.Fatalf("Failed to check table: %v", err)
	}

	if !exists {
		fmt.Println("Creating payment_orders table...")
		_, err = database.DB.Exec(context.Background(), `
			CREATE TABLE payment_orders (
				id SERIAL PRIMARY KEY,
				user_id INT REFERENCES users(id) NOT NULL,
				order_id TEXT UNIQUE NOT NULL,
				payment_id TEXT,
				amount DECIMAL(10,2) NOT NULL,
				status TEXT DEFAULT 'pending',
				payment_gateway TEXT DEFAULT 'razorpay',
				shopkeeper_id INT REFERENCES users(id),
				platform_commission DECIMAL(10,2) DEFAULT 0,
				shopkeeper_amount DECIMAL(10,2),
				copies INT DEFAULT 1,
				print_mode TEXT DEFAULT 'single',
				color_mode TEXT DEFAULT 'bw',
				paper_size TEXT DEFAULT 'A4',
				print_type TEXT DEFAULT 'private',
				comment TEXT,
				created_at TIMESTAMP DEFAULT NOW(),
				paid_at TIMESTAMP,
				expires_at TIMESTAMP,
				file_id INT REFERENCES files(id)
			);
		`)
		if err != nil {
			log.Fatalf("Failed to create payment_orders: %v", err)
		}
		fmt.Println("✓ payment_orders table created")
	} else {
		fmt.Println("✓ payment_orders table already exists")
	}

	// Check if shopkeeper_payouts exists
	err = database.DB.QueryRow(context.Background(),
		"SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'shopkeeper_payouts')").Scan(&exists)

	if err != nil {
		log.Fatalf("Failed to check table: %v", err)
	}

	if !exists {
		fmt.Println("Creating shopkeeper_payouts table...")
		_, err = database.DB.Exec(context.Background(), `
			CREATE TABLE shopkeeper_payouts (
				id SERIAL PRIMARY KEY,
				shopkeeper_id INT REFERENCES users(id) NOT NULL,
				payment_order_id INT REFERENCES payment_orders(id) NOT NULL,
				amount DECIMAL(10,2) NOT NULL,
				status TEXT DEFAULT 'pending',
				payout_method TEXT,
				payout_reference TEXT,
				paid_at TIMESTAMP,
				created_at TIMESTAMP DEFAULT NOW(),
				UNIQUE(shopkeeper_id, payment_order_id)
			);
		`)
		if err != nil {
			log.Fatalf("Failed to create shopkeeper_payouts: %v", err)
		}
		fmt.Println("✓ shopkeeper_payouts table created")
	} else {
		fmt.Println("✓ shopkeeper_payouts table already exists")
	}

	// Create indexes
	fmt.Println("Creating indexes...")
	indexes := []string{
		"CREATE INDEX IF NOT EXISTS idx_payment_orders_user_id ON payment_orders(user_id)",
		"CREATE INDEX IF NOT EXISTS idx_payment_orders_order_id ON payment_orders(order_id)",
		"CREATE INDEX IF NOT EXISTS idx_payment_orders_status ON payment_orders(status)",
		"CREATE INDEX IF NOT EXISTS idx_payment_orders_shopkeeper_id ON payment_orders(shopkeeper_id)",
		"CREATE INDEX IF NOT EXISTS idx_shopkeeper_payouts_shopkeeper_id ON shopkeeper_payouts(shopkeeper_id)",
		"CREATE INDEX IF NOT EXISTS idx_shopkeeper_payouts_status ON shopkeeper_payouts(status)",
	}

	for _, idx := range indexes {
		_, err = database.DB.Exec(context.Background(), idx)
		if err != nil {
			log.Printf("Warning: Failed to create index: %v", err)
		}
	}

	fmt.Println("✓ All indexes created")

	// Add payment columns to files if they don't exist
	fmt.Println("Adding payment columns to files table...")
	_, err = database.DB.Exec(context.Background(), `
		ALTER TABLE files ADD COLUMN IF NOT EXISTS payment_order_id INT REFERENCES payment_orders(id);
		ALTER TABLE files ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid';
		CREATE INDEX IF NOT EXISTS idx_files_payment_order_id ON files(payment_order_id);
		CREATE INDEX IF NOT EXISTS idx_files_payment_status ON files(payment_status);
	`)
	if err != nil {
		log.Printf("Warning: Failed to add payment columns: %v", err)
	} else {
		fmt.Println("✓ Payment columns added to files table")
	}

	fmt.Println("\n✅ Database schema fixed successfully!")
	fmt.Println("You can now access the admin panel and see orders.")
}
