// Package tests_test contains black-box component tests for the dealership service.
package tests_test

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	dealership "assessment"
	"assessment/modules/common/config"
	commonredis "assessment/modules/common/redis"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	componentTestEnabledVariable  = "COMPONENT_TEST"
	componentTestDSNVariable      = "COMPONENT_TEST_POSTGRES_DSN"
	componentTestRedisURLVariable = "COMPONENT_TEST_REDIS_URL"
	superadminEmail               = "component-superadmin@example.test"
	superadminPassword            = "ComponentPass1@"
)

var componentServer *httptest.Server

func TestMain(m *testing.M) {
	if os.Getenv(componentTestEnabledVariable) != "1" {
		os.Exit(m.Run())
	}

	dsn := os.Getenv(componentTestDSNVariable)
	if dsn == "" {
		fmt.Fprintf(os.Stderr, "%s is required when %s=1\n", componentTestDSNVariable, componentTestEnabledVariable)
		os.Exit(2)
	}
	redisURL := os.Getenv(componentTestRedisURLVariable)
	if redisURL == "" {
		fmt.Fprintf(os.Stderr, "%s is required when %s=1\n", componentTestRedisURLVariable, componentTestEnabledVariable)
		os.Exit(2)
	}

	ctx := context.Background()
	database, err := pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect component-test database: %v\n", err)
		os.Exit(2)
	}
	redisClient, err := commonredis.NewClient(ctx, redisURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect component-test Redis: %v\n", err)
		database.Close()
		os.Exit(2)
	}

	privateKeyPEM, publicKeyPEM, err := testKeyPair()
	if err != nil {
		fmt.Fprintf(os.Stderr, "generate component-test signing key: %v\n", err)
		_ = redisClient.Close()
		database.Close()
		os.Exit(2)
	}

	service, err := dealership.New(ctx, database, commonredis.NewIdempotencyStore(redisClient), config.Config{
		PostgresDSN:        dsn,
		RedisURL:           redisURL,
		EmailEncryptionKey: "component-test-email-encryption-key",
		EmailLookupKey:     "component-test-email-lookup-key",
		JWTPrivateKeyPEM:   privateKeyPEM,
		JWTPublicKeyPEM:    publicKeyPEM,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "start component-test service: %v\n", err)
		_ = redisClient.Close()
		database.Close()
		os.Exit(2)
	}

	componentServer = httptest.NewServer(service.Router())
	exitCode := m.Run()
	componentServer.Close()
	_ = service.Close()
	_ = redisClient.Close()
	os.Exit(exitCode)
}

func requireComponentTest(t *testing.T) {
	t.Helper()
	if componentServer == nil {
		t.Skipf("component tests are disabled; set %s=1, %s, and %s to run them", componentTestEnabledVariable, componentTestDSNVariable, componentTestRedisURLVariable)
	}
}

func testKeyPair() (string, string, error) {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return "", "", err
	}
	privateKeyDER, err := x509.MarshalPKCS8PrivateKey(privateKey)
	if err != nil {
		return "", "", err
	}
	publicKeyDER, err := x509.MarshalPKIXPublicKey(&privateKey.PublicKey)
	if err != nil {
		return "", "", err
	}
	privateKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: privateKeyDER})
	publicKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: publicKeyDER})
	return string(privateKeyPEM), string(publicKeyPEM), nil
}

type apiResponse struct {
	statusCode int
	body       json.RawMessage
}

func requestJSON(t *testing.T, method, path, token string, body any) apiResponse {
	t.Helper()
	var requestBody *bytes.Reader
	if body == nil {
		requestBody = bytes.NewReader(nil)
	} else {
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("encode %s %s request: %v", method, path, err)
		}
		requestBody = bytes.NewReader(encoded)
	}

	request, err := http.NewRequestWithContext(t.Context(), method, componentServer.URL+path, requestBody)
	if err != nil {
		t.Fatalf("create %s %s request: %v", method, path, err)
	}
	request.Header.Set("Content-Type", "application/json")
	if method == http.MethodPost || method == http.MethodPut || method == http.MethodPatch {
		request.Header.Set("Idempotency-Id", uuid.NewString())
	}
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	client := &http.Client{Timeout: 10 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		t.Fatalf("perform %s %s request: %v", method, path, err)
	}
	defer response.Body.Close()

	decoded := json.RawMessage{}
	if err := json.NewDecoder(response.Body).Decode(&decoded); err != nil && err.Error() != "EOF" {
		t.Fatalf("decode %s %s response: %v", method, path, err)
	}
	return apiResponse{statusCode: response.StatusCode, body: decoded}
}

func requireStatus(t *testing.T, response apiResponse, want int) {
	t.Helper()
	if response.statusCode != want {
		t.Fatalf("unexpected HTTP status: got %d, want %d; response=%s", response.statusCode, want, response.body)
	}
}

func decodeBody[T any](t *testing.T, response apiResponse) T {
	t.Helper()
	var value T
	if err := json.Unmarshal(response.body, &value); err != nil {
		t.Fatalf("decode response body: %v; response=%s", err, response.body)
	}
	return value
}

func uniqueValue(prefix string) string {
	return prefix + "-" + uuid.NewString()
}

func uniquePhone() string {
	digits := strings.Map(func(character rune) rune {
		if character >= '0' && character <= '9' {
			return character
		}
		return -1
	}, uuid.NewString()+uuid.NewString())
	return "+849" + digits[:10]
}

func uniqueIdentifier(prefix string, length int) string {
	value := prefix + strings.ReplaceAll(uuid.NewString(), "-", "")
	return value[:length]
}

func superadminToken(t *testing.T) string {
	t.Helper()
	response := requestJSON(t, http.MethodPost, "/auth/v1/internal/superadmin", "", map[string]string{
		"email":     superadminEmail,
		"password":  superadminPassword,
		"full_name": "Component Superadmin",
	})
	if response.statusCode != http.StatusCreated && response.statusCode != http.StatusConflict {
		requireStatus(t, response, http.StatusCreated)
	}

	response = requestJSON(t, http.MethodPost, "/auth/v1/sign-in", "", map[string]string{
		"email":    superadminEmail,
		"password": superadminPassword,
	})
	if response.statusCode != http.StatusOK {
		t.Fatalf(
			"component database must be empty on first run, or retain the component test superadmin; got %d signing in as %s: %s",
			response.statusCode,
			superadminEmail,
			response.body,
		)
	}
	result := decodeBody[tokens](t, response)
	if result.AccessToken == "" {
		t.Fatal("superadmin sign-in returned an empty access token")
	}
	return result.AccessToken
}

type tokens struct {
	AccessToken string `json:"access_token"`
}
