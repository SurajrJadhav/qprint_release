package auth

import (
	"crypto/rand"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

const minJWTSecretLength = 32

var jwtSecret []byte

// InitJWTSecret validates and sets the JWT secret. Call once at startup (e.g. from main).
// JWT_SECRET must be set and at least 32 characters. If JWT_SECRET is empty in development,
// a one-time random secret is generated and logged (not suitable for production).
func InitJWTSecret() error {
	s := os.Getenv("JWT_SECRET")
	if s != "" {
		if len(s) < minJWTSecretLength {
			return fmt.Errorf("JWT_SECRET must be at least %d characters (current: %d)", minJWTSecretLength, len(s))
		}
		jwtSecret = []byte(s)
		return nil
	}
	// Development fallback: generate one-time random secret (logged so server restarts lose it)
	if os.Getenv("ENVIRONMENT") == "development" || os.Getenv("TEST_MODE") == "true" {
		b := make([]byte, 32)
		if _, err := rand.Read(b); err != nil {
			return fmt.Errorf("JWT_SECRET not set and failed to generate random secret: %w", err)
		}
		jwtSecret = b
		// Log only that we're using a generated secret, not the value
		fmt.Println("Warning: JWT_SECRET not set; using one-time random secret (set JWT_SECRET for production)")
		return nil
	}
	return fmt.Errorf("JWT_SECRET must be set and at least %d characters in production", minJWTSecretLength)
}

func getJWTSecret() []byte {
	if len(jwtSecret) == 0 {
		// Fallback if InitJWTSecret was never called (e.g. tests)
		return []byte(os.Getenv("JWT_SECRET"))
	}
	return jwtSecret
}

type Claims struct {
	UserID  int    `json:"user_id"`
	Role    string `json:"role"`
	Purpose string `json:"purpose,omitempty"` // "2fa_pending" for login step before TOTP
	jwt.RegisteredClaims
}

func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), 14)
	return string(bytes), err
}

func CheckPasswordHash(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

func GenerateToken(userID int, role string) (string, error) {
	expirationTime := time.Now().Add(7 * 24 * time.Hour) // 7 days
	claims := &Claims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(getJWTSecret())
}

// ValidateToken parses and validates a JWT. Only HMAC (e.g. HS256) is accepted to prevent
// algorithm confusion (e.g. alg:none or RS256 with HMAC key).
func ValidateToken(tokenString string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return getJWTSecret(), nil
	})

	if err != nil {
		return nil, err
	}

	if !token.Valid {
		return nil, errors.New("invalid token")
	}

	return claims, nil
}

// Generate2FAPendingToken issues a short-lived token (5 min) for the 2FA step. Purpose is "2fa_pending".
func Generate2FAPendingToken(userID int) (string, error) {
	expirationTime := time.Now().Add(5 * time.Minute)
	claims := &Claims{
		UserID:  userID,
		Purpose: "2fa_pending",
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(getJWTSecret())
}

// Validate2FAPendingToken parses a token and returns userID only if purpose is "2fa_pending" and valid.
func Validate2FAPendingToken(tokenString string) (userID int, err error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return getJWTSecret(), nil
	})
	if err != nil {
		return 0, err
	}
	if !token.Valid || claims.Purpose != "2fa_pending" {
		return 0, errors.New("invalid or expired 2FA token")
	}
	return claims.UserID, nil
}

// SignupClaims holds email for sign-up token (no user ID; used before account exists).
const SignupTokenPurpose = "signup_pending"

type SignupClaims struct {
	Email   string `json:"email"`
	Purpose string `json:"purpose"`
	jwt.RegisteredClaims
}

// GenerateSignupToken issues a short-lived token (15 min) for completing registration (email verification).
func GenerateSignupToken(email string) (string, error) {
	expirationTime := time.Now().Add(15 * time.Minute)
	claims := &SignupClaims{
		Email:   email,
		Purpose: SignupTokenPurpose,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(getJWTSecret())
}

// ValidateSignupToken parses a token and returns verified email.
func ValidateSignupToken(tokenString string) (email string, err error) {
	claims := &SignupClaims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return getJWTSecret(), nil
	})
	if err != nil {
		return "", err
	}
	if !token.Valid || claims.Purpose != SignupTokenPurpose {
		return "", errors.New("invalid or expired signup token")
	}
	return claims.Email, nil
}
