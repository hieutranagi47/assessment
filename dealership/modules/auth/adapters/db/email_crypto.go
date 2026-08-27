package db

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
)

// emailCrypto keeps the encrypted value and its deterministic, keyed lookup
// token separate. The lookup key is deliberately independent from the
// encryption key so a disclosure of one does not disclose the other.
type emailCrypto struct {
	block     cipher.AEAD
	lookupKey []byte
}

func newEmailCrypto(encryptionKey, lookupKey string) (emailCrypto, error) {
	if encryptionKey == "" || lookupKey == "" {
		return emailCrypto{}, errors.New("email encryption and lookup keys are required")
	}
	key := sha256.Sum256([]byte(encryptionKey))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return emailCrypto{}, fmt.Errorf("create email cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return emailCrypto{}, fmt.Errorf("create email AEAD: %w", err)
	}
	return emailCrypto{block: aead, lookupKey: []byte(lookupKey)}, nil
}

func (c emailCrypto) encrypt(email string) ([]byte, error) {
	nonce := make([]byte, c.block.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("generate email encryption nonce: %w", err)
	}
	return c.block.Seal(nonce, nonce, []byte(email), nil), nil
}

func (c emailCrypto) decrypt(value []byte) (string, error) {
	nonceSize := c.block.NonceSize()
	if len(value) < nonceSize {
		return "", errors.New("invalid encrypted email")
	}
	plain, err := c.block.Open(nil, value[:nonceSize], value[nonceSize:], nil)
	if err != nil {
		return "", errors.New("could not decrypt user email")
	}
	return string(plain), nil
}

func (c emailCrypto) lookup(email string) []byte {
	mac := hmac.New(sha256.New, c.lookupKey)
	_, _ = mac.Write([]byte(email))
	return mac.Sum(nil)
}
