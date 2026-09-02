// Package password contains infrastructure implementations of password
// hashing used by the auth application service.
package password

import (
	"strings"

	"assessment/modules/auth/domain"

	"golang.org/x/crypto/bcrypt"
)

// BcryptHasher implements the app password-hashing port using bcrypt's
// default work factor.
type BcryptHasher struct{}

// Hash creates a bcrypt password hash and rejects blank passwords.
func (BcryptHasher) Hash(value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", domain.ErrInvalidPassword
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(value), bcrypt.DefaultCost)
	return string(hash), err
}

// Matches compares a plaintext password with a bcrypt hash without exposing
// comparison details to callers.
func (BcryptHasher) Matches(hash, value string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(value)) == nil
}
