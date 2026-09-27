package storage

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type Storage interface {
	Upload(ctx context.Context, file io.Reader, filename string) (string, error)
	Download(ctx context.Context, filePath string) (io.ReadCloser, error)
	Delete(ctx context.Context, filePath string) error
	GetFile(ctx context.Context, filePath string) (io.ReadCloser, error)
}

type LocalStorage struct {
	baseDir string
}

type S3Storage struct {
	client     *s3.Client
	uploader   *manager.Uploader
	downloader *manager.Downloader
	bucket     string
	region     string
}

// NewStorage creates a storage instance based on environment configuration
// Returns S3Storage if AWS credentials are configured, otherwise LocalStorage
// Can be forced to use local storage with USE_LOCAL_STORAGE=true
func NewStorage() (Storage, error) {
	// Check if local storage is forced via environment variable
	useLocalStorage := os.Getenv("USE_LOCAL_STORAGE")
	if useLocalStorage == "true" || useLocalStorage == "1" {
		fmt.Println("📁 Using LOCAL storage (forced by USE_LOCAL_STORAGE=true)")
		return NewLocalStorage(), nil
	}

	// Check if S3 is configured
	bucket := os.Getenv("AWS_S3_BUCKET")
	region := os.Getenv("AWS_REGION")
	accessKey := os.Getenv("AWS_ACCESS_KEY_ID")
	secretKey := os.Getenv("AWS_SECRET_ACCESS_KEY")

	// If S3 credentials are provided, use S3
	if bucket != "" && region != "" && accessKey != "" && secretKey != "" {
		fmt.Println("☁️  Using S3 storage (AWS credentials configured)")
		return NewS3Storage(bucket, region)
	}

	// Otherwise, use local storage
	fmt.Println("📁 Using LOCAL storage (no S3 credentials or USE_LOCAL_STORAGE not set)")
	return NewLocalStorage(), nil
}

// NewLocalStorage creates a local file storage instance
func NewLocalStorage() Storage {
	baseDir := os.Getenv("UPLOADS_DIR")
	if baseDir == "" {
		baseDir = "uploads"
	}

	// Create directory if it doesn't exist
	if _, err := os.Stat(baseDir); os.IsNotExist(err) {
		os.MkdirAll(baseDir, 0755)
	}

	return &LocalStorage{baseDir: baseDir}
}

// NewS3Storage creates an S3 storage instance
func NewS3Storage(bucket, region string) (Storage, error) {
	cfg, err := config.LoadDefaultConfig(context.Background(),
		config.WithRegion(region),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	client := s3.NewFromConfig(cfg)
	uploader := manager.NewUploader(client)
	downloader := manager.NewDownloader(client)

	return &S3Storage{
		client:     client,
		uploader:   uploader,
		downloader: downloader,
		bucket:     bucket,
		region:     region,
	}, nil
}

// LocalStorage implementations

func (s *LocalStorage) Upload(ctx context.Context, file io.Reader, filename string) (string, error) {
	filePath := filepath.Join(s.baseDir, filename)
	
	// Create directory if it doesn't exist
	dir := filepath.Dir(filePath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("failed to create directory: %w", err)
	}

	dst, err := os.Create(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to create file: %w", err)
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		return "", fmt.Errorf("failed to write file: %w", err)
	}

	return filePath, nil
}

func (s *LocalStorage) Download(ctx context.Context, filePath string) (io.ReadCloser, error) {
	// Check if this is an S3 path
	if strings.HasPrefix(filePath, "s3://") {
		// Even with USE_LOCAL_STORAGE=true, if file is in S3, we need S3 to access it
		// Try to use S3 storage if credentials are available
		bucket := os.Getenv("AWS_S3_BUCKET")
		region := os.Getenv("AWS_REGION")
		accessKey := os.Getenv("AWS_ACCESS_KEY_ID")
		secretKey := os.Getenv("AWS_SECRET_ACCESS_KEY")
		
		if bucket != "" && region != "" && accessKey != "" && secretKey != "" {
			s3Storage, err := NewS3Storage(bucket, region)
			if err == nil {
				fmt.Printf("⚠️  File is in S3 (%s), using S3 storage to download (even with USE_LOCAL_STORAGE=true)\n", filePath)
				return s3Storage.Download(ctx, filePath)
			}
		}
		
		// No S3 credentials - provide helpful error
		return nil, fmt.Errorf("file is stored in S3 (%s) but S3 credentials are not configured. To access S3 files locally, set AWS_S3_BUCKET, AWS_REGION, AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY in your .env file", filePath)
	}
	
	// Defense in depth: ensure path does not escape baseDir (e.g. if DB were compromised)
	absBase, err := filepath.Abs(s.baseDir)
	if err != nil {
		return nil, fmt.Errorf("failed to resolve base dir: %w", err)
	}
	cleanPath := filepath.Clean(filePath)
	absPath, err := filepath.Abs(cleanPath)
	if err != nil {
		return nil, fmt.Errorf("invalid file path: %w", err)
	}
	rel, err := filepath.Rel(absBase, absPath)
	if err != nil || strings.HasPrefix(rel, "..") {
		return nil, fmt.Errorf("file path escapes base directory")
	}

	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("file not found at local path (file may have been uploaded to S3 on production)")
	}

	file, err := os.Open(absPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open file: %w", err)
	}
	return file, nil
}

func (s *LocalStorage) Delete(ctx context.Context, filePath string) error {
	if strings.HasPrefix(filePath, "s3://") {
		return nil // S3 paths are not deleted by LocalStorage
	}
	absBase, err := filepath.Abs(s.baseDir)
	if err != nil {
		return fmt.Errorf("failed to resolve base dir: %w", err)
	}
	absPath, err := filepath.Abs(filepath.Clean(filePath))
	if err != nil {
		return fmt.Errorf("invalid file path: %w", err)
	}
	rel, err := filepath.Rel(absBase, absPath)
	if err != nil || strings.HasPrefix(rel, "..") {
		return fmt.Errorf("file path escapes base directory")
	}
	if err := os.Remove(absPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to delete file: %w", err)
	}
	return nil
}

func (s *LocalStorage) GetFile(ctx context.Context, filePath string) (io.ReadCloser, error) {
	// Check if this is an S3 path
	if strings.HasPrefix(filePath, "s3://") {
		// Even with USE_LOCAL_STORAGE=true, if file is in S3, we need S3 to access it
		// Try to initialize S3 storage if credentials are available
		bucket := os.Getenv("AWS_S3_BUCKET")
		region := os.Getenv("AWS_REGION")
		accessKey := os.Getenv("AWS_ACCESS_KEY_ID")
		secretKey := os.Getenv("AWS_SECRET_ACCESS_KEY")
		
		if bucket != "" && region != "" && accessKey != "" && secretKey != "" {
			// We have S3 credentials, use S3 storage for this file
			s3Storage, err := NewS3Storage(bucket, region)
			if err == nil {
				fmt.Printf("⚠️  File is in S3 (%s), using S3 storage to access (even with USE_LOCAL_STORAGE=true)\n", filePath)
				return s3Storage.GetFile(ctx, filePath)
			}
		}
		
		// No S3 credentials available, return helpful error
		return nil, fmt.Errorf("file is stored in S3 (%s) but S3 credentials are not configured. To access S3 files locally, set AWS_S3_BUCKET, AWS_REGION, AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY in your .env file. Alternatively, use a local database with locally uploaded files", filePath)
	}
	
	return s.Download(ctx, filePath)
}

// S3Storage implementations

func (s *S3Storage) Upload(ctx context.Context, file io.Reader, filename string) (string, error) {
	// Use filename as S3 key
	key := filename

	// Upload to S3
	_, err := s.uploader.Upload(ctx, &s3.PutObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
		Body:   file,
	})
	if err != nil {
		return "", fmt.Errorf("failed to upload to S3: %w", err)
	}

	// Return S3 key as file path (we'll use this to identify S3 files)
	return fmt.Sprintf("s3://%s/%s", s.bucket, key), nil
}

func (s *S3Storage) Download(ctx context.Context, filePath string) (io.ReadCloser, error) {
	key := s.extractKey(filePath)
	if strings.Contains(key, "..") {
		return nil, fmt.Errorf("invalid S3 key: path traversal not allowed")
	}

	// Use GetObject directly for streaming
	result, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to download from S3: %w", err)
	}

	return result.Body, nil
}

func (s *S3Storage) Delete(ctx context.Context, filePath string) error {
	key := s.extractKey(filePath)
	if strings.Contains(key, "..") {
		return fmt.Errorf("invalid S3 key: path traversal not allowed")
	}

	_, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return fmt.Errorf("failed to delete from S3: %w", err)
	}

	return nil
}

func (s *S3Storage) GetFile(ctx context.Context, filePath string) (io.ReadCloser, error) {
	return s.Download(ctx, filePath)
}

// extractKey extracts the S3 key from a file path
// Handles both "s3://bucket/key" format and plain key format
func (s *S3Storage) extractKey(filePath string) string {
	if strings.HasPrefix(filePath, "s3://") {
		// Remove "s3://bucket/" prefix
		parts := strings.SplitN(filePath, "/", 4)
		if len(parts) >= 4 {
			return parts[3]
		}
	}
	// If it's already just a key, return it
	return filePath
}
