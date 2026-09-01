package db

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"errors"
	"fmt"
	"io"

	"golang.org/x/crypto/argon2"
)

const (
	emailPasswordSaltSize = 16
	emailKeySize          = 32
)

// passwordEmailCrypto protects an additional email copy with a key derived
// from the password supplied for the current request. Its salt is stored with
// the ciphertext; the password itself is never persisted.
type passwordEmailCrypto struct{}

func (passwordEmailCrypto) encrypt(email, password string) ([]byte, []byte, error) {
	if password == "" {
		return nil, nil, errors.New("email encryption password is required")
	}

	salt := make([]byte, emailPasswordSaltSize)
	if _, err := io.ReadFull(rand.Reader, salt); err != nil {
		return nil, nil, fmt.Errorf("generate email password salt: %w", err)
	}

	value, err := encryptEmailWithKey(email, passwordEmailKey(password, salt))
	if err != nil {
		return nil, nil, err
	}
	return value, salt, nil
}

func (passwordEmailCrypto) decrypt(value, salt []byte, password string) (string, error) {
	if password == "" || len(salt) != emailPasswordSaltSize {
		return "", errors.New("invalid password-encrypted email")
	}
	return decryptEmailWithKey(value, passwordEmailKey(password, salt))
}

func passwordEmailKey(password string, salt []byte) []byte {
	return argon2.IDKey([]byte(password), salt, 3, 64*1024, 4, emailKeySize)
}

func encryptEmailWithKey(email string, key []byte) ([]byte, error) {
	defer clear(key)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create password email cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("create password email AEAD: %w", err)
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, fmt.Errorf("generate password email nonce: %w", err)
	}
	return aead.Seal(nonce, nonce, []byte(email), nil), nil
}

func decryptEmailWithKey(value, key []byte) (string, error) {
	defer clear(key)
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("create password email cipher: %w", err)
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("create password email AEAD: %w", err)
	}
	nonceSize := aead.NonceSize()
	if len(value) < nonceSize {
		return "", errors.New("invalid password-encrypted email")
	}
	plain, err := aead.Open(nil, value[:nonceSize], value[nonceSize:], nil)
	if err != nil {
		return "", errors.New("could not decrypt password-encrypted email")
	}
	return string(plain), nil
}
