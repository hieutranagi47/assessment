package db

import (
	"crypto/hmac"
	"crypto/sha256"
	"errors"
)

// emailLookup creates a deterministic, keyed token for normalized email
// addresses. The token supports sign-in and uniqueness checks without storing
// the address unless the user has opted in to delivery.
type emailLookup struct {
	key []byte
}

func newEmailLookup(key string) (emailLookup, error) {
	if key == "" {
		return emailLookup{}, errors.New("email lookup key is required")
	}
	return emailLookup{key: []byte(key)}, nil
}

func (c emailLookup) lookup(email string) []byte {
	mac := hmac.New(sha256.New, c.key)
	_, _ = mac.Write([]byte(email))
	return mac.Sum(nil)
}
