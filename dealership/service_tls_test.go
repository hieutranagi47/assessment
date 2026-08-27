package authservice

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"testing"
)

func TestNewTLSConfigBuildsCertificateFromMatchingRSAEnvironmentKeys(t *testing.T) {
	privateKey, publicKey := testRSAKeyPair(t)

	config, err := newTLSConfig(privateKey, publicKey)
	if err != nil {
		t.Fatalf("newTLSConfig() error = %v", err)
	}
	if config.MinVersion < tls.VersionTLS12 {
		t.Errorf("newTLSConfig() MinVersion = %x, want TLS 1.2 or newer", config.MinVersion)
	}
	if len(config.Certificates) != 1 {
		t.Fatalf("newTLSConfig() certificates = %d, want 1", len(config.Certificates))
	}
	certificate, err := x509.ParseCertificate(config.Certificates[0].Certificate[0])
	if err != nil {
		t.Fatalf("parse generated certificate: %v", err)
	}
	if err := certificate.VerifyHostname("localhost"); err != nil {
		t.Fatalf("generated certificate does not verify localhost: %v", err)
	}
}

func TestNewTLSConfigRejectsMismatchedRSAKeys(t *testing.T) {
	privateKey, _ := testRSAKeyPair(t)
	_, publicKey := testRSAKeyPair(t)

	if _, err := newTLSConfig(privateKey, publicKey); err == nil {
		t.Fatal("newTLSConfig() error = nil, want mismatched-key error")
	}
}

func testRSAKeyPair(t *testing.T) ([]byte, []byte) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate RSA key: %v", err)
	}
	privateKey, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("marshal RSA private key: %v", err)
	}
	publicKey, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatalf("marshal RSA public key: %v", err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: privateKey}), pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: publicKey})
}
