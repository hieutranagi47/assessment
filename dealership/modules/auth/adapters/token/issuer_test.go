package token

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"testing"
	"time"

	"assessment/modules/auth/domain"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestIssuerCreatesTokensRecognizedByTheAuthService(t *testing.T) {
	now := time.Date(2026, 8, 12, 0, 0, 0, 0, time.UTC)
	issuer := testIssuer(t)
	issuer.now = func() time.Time { return now }
	user, err := domain.NewUser(uuid.New(), "person@example.com", "Person", "hash", now)
	require.NoError(t, err)

	tokens, err := issuer.Issue(user, domain.RoleAdmin)
	require.NoError(t, err)
	identity, err := issuer.VerifyAccess(tokens.AccessToken)
	require.NoError(t, err)
	require.Equal(t, user.ID(), identity.UserID)
	require.Equal(t, "free", identity.Plan)

	accessClaims := claims{}
	_, err = jwt.ParseWithClaims(tokens.AccessToken, &accessClaims, func(*jwt.Token) (any, error) {
		return &issuer.privateKey.PublicKey, nil
	}, jwt.WithTimeFunc(issuer.now))
	require.NoError(t, err)
	require.Equal(t, domain.RoleAdmin, accessClaims.Role)

	refreshIdentity, err := issuer.VerifyRefresh(tokens.RefreshToken)
	require.NoError(t, err)
	require.Equal(t, user.TokenVersion(), refreshIdentity.TokenVersion)

	refreshClaims := claims{}
	_, err = jwt.ParseWithClaims(tokens.RefreshToken, &refreshClaims, func(*jwt.Token) (any, error) {
		return &issuer.privateKey.PublicKey, nil
	}, jwt.WithTimeFunc(issuer.now))
	require.NoError(t, err)
	require.Empty(t, refreshClaims.Role)
}

func testIssuer(t *testing.T) *Issuer {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	privateKey := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	publicKey, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	require.NoError(t, err)
	issuer, err := NewIssuer(privateKey, pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: publicKey}))
	require.NoError(t, err)
	return issuer
}
