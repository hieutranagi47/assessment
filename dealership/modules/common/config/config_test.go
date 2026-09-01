package config

import (
	"strings"
	"testing"
)

func TestLoadRequiresSecurityAndInfrastructureSettings(t *testing.T) {
	required := map[string]string{
		"POSTGRES_DSN":        "postgres://example",
		"REDIS_URL":           "redis://example:6379/0",
		"EMAIL_LOOKUP_KEY":    "lookup-key",
		"RSA_PRIVATE_KEY_PEM": "private-key",
		"RSA_PUBLIC_KEY_PEM":  "public-key",
	}
	for name, value := range required {
		t.Setenv(name, value)
	}

	for missing := range required {
		t.Run(missing, func(t *testing.T) {
			t.Setenv(missing, "")

			_, err := Load()
			if err == nil {
				t.Fatal("Load() error = nil, want required-setting error")
			}
			if !strings.Contains(err.Error(), missing) {
				t.Errorf("Load() error = %q, want it to name %q", err, missing)
			}
		})
	}
}

func TestLoadUsesListenerPortDefaults(t *testing.T) {
	for name, value := range map[string]string{
		"POSTGRES_DSN":        "postgres://example",
		"REDIS_URL":           "redis://example:6379/0",
		"EMAIL_LOOKUP_KEY":    "lookup-key",
		"RSA_PRIVATE_KEY_PEM": "private-key",
		"RSA_PUBLIC_KEY_PEM":  "public-key",
		"SERVER_PORT":         "",
		"SERVER_PORT_TLS":     "",
	} {
		t.Setenv(name, value)
	}

	config, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if config.HTTPPort != "8080" || config.HTTPSPort != "8443" {
		t.Errorf("Load() ports = (%q, %q), want (8080, 8443)", config.HTTPPort, config.HTTPSPort)
	}
}
