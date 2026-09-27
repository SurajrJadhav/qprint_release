package database

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var DB *pgxpool.Pool

func Connect() {
	dsn := os.Getenv("DATABASE_URL")

	if dsn == "" {
		log.Fatal("DATABASE_URL environment variable is not set")
	}

	// In production, enforce SSL: require sslmode=require (never sslmode=disable), auto-add if missing
	if os.Getenv("ENVIRONMENT") == "production" {
		dsnLower := strings.ToLower(dsn)
		if strings.Contains(dsnLower, "sslmode=disable") {
			log.Fatal("DATABASE_URL must not use sslmode=disable in production. Use sslmode=require (e.g. postgres://...?sslmode=require).")
		}
		if !strings.Contains(dsnLower, "sslmode=") {
			if strings.Contains(dsn, "?") {
				dsn = dsn + "&sslmode=require"
			} else {
				dsn = dsn + "?sslmode=require"
			}
		}
	}

	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		log.Fatalf("Unable to parse database config: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	DB, err = pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		log.Fatalf("Unable to create connection pool: %v", err)
	}

	if err := DB.Ping(ctx); err != nil {
		log.Fatalf("Unable to ping database: %v", err)
	}

	fmt.Println("Connected to PostgreSQL database")
}

func Close() {
	if DB != nil {
		DB.Close()
	}
}
