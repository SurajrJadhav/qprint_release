package auth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const googleCertsURL = "https://www.googleapis.com/oauth2/v3/certs"

var (
	googleClientIDsOnce sync.Once
	googleClientIDs     []string

	googleKeysMu     sync.RWMutex
	googleKeys       map[string]*rsa.PublicKey
	googleKeysExpiry time.Time
)

// GoogleClientIDs returns allowed OAuth client IDs for ID token audience checks.
// Set GOOGLE_CLIENT_IDS to a comma-separated list (Web + Android + iOS client IDs).
func GoogleClientIDs() []string {
	googleClientIDsOnce.Do(func() {
		raw := strings.TrimSpace(os.Getenv("GOOGLE_CLIENT_IDS"))
		if raw == "" {
			return
		}
		for _, part := range strings.Split(raw, ",") {
			id := strings.TrimSpace(part)
			if id != "" {
				googleClientIDs = append(googleClientIDs, id)
			}
		}
	})
	return googleClientIDs
}

// GoogleIdentity is the verified identity from a Google ID token.
type GoogleIdentity struct {
	Sub           string
	Email         string
	EmailVerified bool
	Name          string
}

type googleClaims struct {
	Email         string `json:"email"`
	EmailVerified any    `json:"email_verified"`
	Name          string `json:"name"`
	jwt.RegisteredClaims
}

// VerifyGoogleIDToken validates a Google ID token against configured client IDs.
func VerifyGoogleIDToken(ctx context.Context, rawToken string) (*GoogleIdentity, error) {
	audiences := GoogleClientIDs()
	if len(audiences) == 0 {
		return nil, fmt.Errorf("Google Sign-In is not configured")
	}
	rawToken = strings.TrimSpace(rawToken)
	if rawToken == "" {
		return nil, fmt.Errorf("id_token is required")
	}

	keys, err := getGooglePublicKeys(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to load Google keys: %w", err)
	}

	claims := &googleClaims{}
	parsed, err := jwt.ParseWithClaims(rawToken, claims, func(token *jwt.Token) (interface{}, error) {
		if token.Method.Alg() != jwt.SigningMethodRS256.Alg() {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		kid, _ := token.Header["kid"].(string)
		if kid == "" {
			return nil, fmt.Errorf("missing kid")
		}
		key, ok := keys[kid]
		if !ok {
			return nil, fmt.Errorf("unknown kid")
		}
		return key, nil
	})
	if err != nil || !parsed.Valid {
		if err == nil {
			err = fmt.Errorf("invalid token")
		}
		return nil, fmt.Errorf("invalid Google token: %w", err)
	}

	issOK := claims.Issuer == "https://accounts.google.com" || claims.Issuer == "accounts.google.com"
	if !issOK {
		return nil, fmt.Errorf("invalid Google token issuer")
	}

	audOK := false
	for _, want := range audiences {
		for _, got := range claims.Audience {
			if got == want {
				audOK = true
				break
			}
		}
		if audOK {
			break
		}
	}
	if !audOK {
		return nil, fmt.Errorf("invalid Google token audience")
	}

	email := strings.TrimSpace(strings.ToLower(claims.Email))
	if email == "" {
		return nil, fmt.Errorf("Google account has no email")
	}
	verified := false
	switch v := claims.EmailVerified.(type) {
	case bool:
		verified = v
	case string:
		verified = strings.EqualFold(v, "true")
	}
	if !verified {
		return nil, fmt.Errorf("Google email is not verified")
	}
	name := strings.TrimSpace(claims.Name)
	if name == "" {
		name = strings.Split(email, "@")[0]
	}
	if len(name) > 50 {
		name = name[:50]
	}
	if claims.Subject == "" {
		return nil, fmt.Errorf("Google token missing subject")
	}
	return &GoogleIdentity{
		Sub:           claims.Subject,
		Email:         email,
		EmailVerified: true,
		Name:          name,
	}, nil
}

type googleCertsResponse struct {
	Keys []struct {
		Kid string `json:"kid"`
		Kty string `json:"kty"`
		Alg string `json:"alg"`
		N   string `json:"n"`
		E   string `json:"e"`
	} `json:"keys"`
}

func getGooglePublicKeys(ctx context.Context) (map[string]*rsa.PublicKey, error) {
	googleKeysMu.RLock()
	if googleKeys != nil && time.Now().Before(googleKeysExpiry) {
		defer googleKeysMu.RUnlock()
		return googleKeys, nil
	}
	googleKeysMu.RUnlock()

	googleKeysMu.Lock()
	defer googleKeysMu.Unlock()
	if googleKeys != nil && time.Now().Before(googleKeysExpiry) {
		return googleKeys, nil
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, googleCertsURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("certs HTTP %d", resp.StatusCode)
	}

	var body googleCertsResponse
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}

	keys := make(map[string]*rsa.PublicKey, len(body.Keys))
	for _, k := range body.Keys {
		if k.Kty != "RSA" || k.Kid == "" {
			continue
		}
		pub, err := jwkToRSAPublicKey(k.N, k.E)
		if err != nil {
			continue
		}
		keys[k.Kid] = pub
	}
	if len(keys) == 0 {
		return nil, fmt.Errorf("no Google RSA keys found")
	}

	// Cache until near Cache-Control max-age, default 1 hour.
	expiry := time.Now().Add(time.Hour)
	if cc := resp.Header.Get("Cache-Control"); cc != "" {
		for _, part := range strings.Split(cc, ",") {
			part = strings.TrimSpace(part)
			if strings.HasPrefix(part, "max-age=") {
				var sec int
				if _, err := fmt.Sscanf(part, "max-age=%d", &sec); err == nil && sec > 60 {
					expiry = time.Now().Add(time.Duration(sec) * time.Second)
				}
			}
		}
	}
	googleKeys = keys
	googleKeysExpiry = expiry
	return googleKeys, nil
}

func jwkToRSAPublicKey(nB64, eB64 string) (*rsa.PublicKey, error) {
	nb, err := base64.RawURLEncoding.DecodeString(nB64)
	if err != nil {
		return nil, err
	}
	eb, err := base64.RawURLEncoding.DecodeString(eB64)
	if err != nil {
		return nil, err
	}
	n := new(big.Int).SetBytes(nb)
	e := 0
	for _, b := range eb {
		e = e<<8 + int(b)
	}
	if e == 0 {
		return nil, fmt.Errorf("invalid exponent")
	}
	return &rsa.PublicKey{N: n, E: e}, nil
}
