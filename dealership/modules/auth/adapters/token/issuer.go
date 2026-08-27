package token

import (
	"crypto/rsa"
	"errors"
	"fmt"
	"time"

	"assessment/modules/auth/app"
	"assessment/modules/auth/domain"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

const (
	accessLifetime  = 15 * time.Minute
	refreshLifetime = 7 * 24 * time.Hour
)

// Issuer signs JWTs with RS256 and verifies them with the matching public key.
// Keeping signing and verification keys separate allows other services to verify
// access tokens without receiving the private key.
type Issuer struct {
	privateKey *rsa.PrivateKey
	publicKey  *rsa.PublicKey
	now        func() time.Time
}

func NewIssuer(privateKeyPEM, publicKeyPEM []byte) (*Issuer, error) {
	privateKey, err := jwt.ParseRSAPrivateKeyFromPEM(privateKeyPEM)
	if err != nil {
		return nil, fmt.Errorf("parse RSA private key: %w", err)
	}
	publicKey, err := jwt.ParseRSAPublicKeyFromPEM(publicKeyPEM)
	if err != nil {
		return nil, fmt.Errorf("parse RSA public key: %w", err)
	}
	return &Issuer{privateKey: privateKey, publicKey: publicKey, now: time.Now}, nil
}

// Issue creates a short-lived access token and a longer-lived refresh token
// carrying the user's current token version.
func (i *Issuer) Issue(user domain.User) (app.Tokens, error) {
	access, err := i.sign(user, "access", accessLifetime)
	if err != nil {
		return app.Tokens{}, err
	}
	refresh, err := i.sign(user, "refresh", refreshLifetime)
	if err != nil {
		return app.Tokens{}, err
	}
	return app.Tokens{AccessToken: access, ExpiresIn: int(accessLifetime.Seconds()), TokenType: "Bearer", RefreshToken: refresh}, nil
}

// VerifyAccess accepts only a valid access-token JWT.
func (i *Issuer) VerifyAccess(raw string) (app.Identity, error) { return i.verify(raw, "access") }

// VerifyRefresh accepts only a valid refresh-token JWT.
func (i *Issuer) VerifyRefresh(raw string) (app.Identity, error) { return i.verify(raw, "refresh") }

type claims struct {
	UserID       string `json:"user_id"`
	TokenVersion int    `json:"token_version"`
	Plan         string `json:"plan"`
	Type         string `json:"type"`
	jwt.RegisteredClaims
}

func (i *Issuer) sign(user domain.User, kind string, lifetime time.Duration) (string, error) {
	value := claims{
		UserID:       user.ID().String(),
		TokenVersion: user.TokenVersion(),
		Plan:         "free",
		Type:         kind,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(i.now()),
			ExpiresAt: jwt.NewNumericDate(i.now().Add(lifetime)),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodRS256, value).SignedString(i.privateKey)
}

// verify enforces RS256, registered-claim validity, token kind, UUID shape,
// and a positive token version before returning an application identity.
func (i *Issuer) verify(raw, kind string) (app.Identity, error) {
	value := claims{}
	parsed, err := jwt.ParseWithClaims(raw, &value, func(parsed *jwt.Token) (any, error) {
		if parsed.Method.Alg() != jwt.SigningMethodRS256.Alg() {
			return nil, errors.New("unexpected signing method")
		}
		return i.publicKey, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodRS256.Alg()}), jwt.WithTimeFunc(i.now))
	if err != nil || !parsed.Valid || value.Type != kind {
		return app.Identity{}, errors.New("invalid token")
	}
	id, err := uuid.Parse(value.UserID)
	if err != nil || id == uuid.Nil || value.TokenVersion < 1 {
		return app.Identity{}, errors.New("invalid token")
	}
	return app.Identity{UserID: id, TokenVersion: value.TokenVersion, Plan: value.Plan}, nil
}
