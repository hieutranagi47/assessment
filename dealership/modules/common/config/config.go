package config

import (
	"fmt"
	"os"
)

// Config is the explicit runtime configuration assembled at the composition
// root. Domain and application packages never read process environment values.
type Config struct {
	PostgresDSN        string
	EmailEncryptionKey string
	EmailLookupKey     string
	JWTPrivateKeyPEM   string
	JWTPublicKeyPEM    string
	HTTPPort           string
	HTTPSPort          string
}

// Load reads required runtime settings from the environment and applies
// defaults for listener ports.
func Load() (Config, error) {
	config := Config{
		PostgresDSN:        os.Getenv("POSTGRES_DSN"),
		EmailEncryptionKey: os.Getenv("EMAIL_ENCRYPTION_KEY"),
		EmailLookupKey:     os.Getenv("EMAIL_LOOKUP_KEY"),
		JWTPrivateKeyPEM:   os.Getenv("RSA_PRIVATE_KEY_PEM"),
		JWTPublicKeyPEM:    os.Getenv("RSA_PUBLIC_KEY_PEM"),
		HTTPPort:           valueOrDefault("SERVER_PORT", "8080"),
		HTTPSPort:          valueOrDefault("SERVER_PORT_TLS", "8443"),
	}
	if config.PostgresDSN == "" || config.EmailEncryptionKey == "" || config.EmailLookupKey == "" || config.JWTPrivateKeyPEM == "" || config.JWTPublicKeyPEM == "" {
		return Config{}, fmt.Errorf("POSTGRES_DSN, EMAIL_ENCRYPTION_KEY, EMAIL_LOOKUP_KEY, RSA_PRIVATE_KEY_PEM, and RSA_PUBLIC_KEY_PEM are required")
	}
	return config, nil
}

// valueOrDefault returns an environment value when present, otherwise the
// supplied fallback.
func valueOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
