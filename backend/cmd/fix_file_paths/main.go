package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/joho/godotenv"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	// Load .env file
	if err := godotenv.Overload(".env"); err != nil {
		if err := godotenv.Overload("backend/.env"); err != nil {
			log.Println("No .env file found, using environment variables")
		}
	}

	// Connect to database
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL environment variable is not set")
	}

	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		log.Fatalf("Unable to parse database config: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	db, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		log.Fatalf("Unable to create connection pool: %v", err)
	}
	defer db.Close()

	if err := db.Ping(ctx); err != nil {
		log.Fatalf("Unable to ping database: %v", err)
	}

	fmt.Println("✅ Connected to database")
	fmt.Println()

	// Get all files with S3 paths
	rows, err := db.Query(ctx, "SELECT id, file_path FROM files WHERE file_path LIKE 's3://%'")
	if err != nil {
		log.Fatalf("Error querying files: %v", err)
	}
	defer rows.Close()

	var filesToUpdate []struct {
		ID       int
		FilePath string
	}

	for rows.Next() {
		var id int
		var filePath string
		if err := rows.Scan(&id, &filePath); err != nil {
			continue
		}
		filesToUpdate = append(filesToUpdate, struct {
			ID       int
			FilePath string
		}{id, filePath})
	}

	if len(filesToUpdate) == 0 {
		fmt.Println("✅ No files with S3 paths found. All files are already using local paths.")
		return
	}

	fmt.Printf("Found %d files with S3 paths:\n", len(filesToUpdate))
	fmt.Println()
	for _, f := range filesToUpdate {
		fmt.Printf("  ID: %d, Path: %s\n", f.ID, f.FilePath)
	}
	fmt.Println()

	// Extract filename from S3 path and convert to local path
	fmt.Println("Converting S3 paths to local paths...")
	fmt.Println()

	uploadsDir := os.Getenv("UPLOADS_DIR")
	if uploadsDir == "" {
		uploadsDir = "uploads"
	}

	updated := 0
	for _, f := range filesToUpdate {
		// Extract filename from S3 path: s3://bucket/filename -> filename
		// Or: s3://bucket/path/to/file -> path/to/file
		var localPath string
		if strings.HasPrefix(f.FilePath, "s3://") {
			// Remove s3://bucket/ prefix
			parts := strings.SplitN(f.FilePath, "/", 4)
			if len(parts) >= 4 {
				// parts[3] is the path after s3://bucket/
				localPath = filepath.Join(uploadsDir, parts[3])
			} else {
				// Fallback: just use filename
				filename := filepath.Base(f.FilePath)
				localPath = filepath.Join(uploadsDir, filename)
			}
		} else {
			continue
		}

		// Update database
		_, err := db.Exec(ctx, "UPDATE files SET file_path = $1 WHERE id = $2", localPath, f.ID)
		if err != nil {
			fmt.Printf("❌ Error updating file ID %d: %v\n", f.ID, err)
			continue
		}

		fmt.Printf("✅ Updated file ID %d: %s -> %s\n", f.ID, f.FilePath, localPath)
		updated++
	}

	fmt.Println()
	fmt.Printf("✅ Successfully updated %d/%d files\n", updated, len(filesToUpdate))
	fmt.Println()
	fmt.Println("⚠️  NOTE: This only updates the database paths.")
	fmt.Println("   The actual files still need to be downloaded from S3 and placed in the local 'uploads' folder.")
	fmt.Println("   Or upload new files locally to test.")
}
