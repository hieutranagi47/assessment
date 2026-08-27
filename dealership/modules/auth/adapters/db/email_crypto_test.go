package db

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestEmailCryptoEncryptDecryptAndLookup(t *testing.T) {
	t.Parallel()

	crypto, err := newEmailCrypto("encryption secret", "lookup secret")
	require.NoError(t, err)

	first, err := crypto.encrypt("person@example.com")
	require.NoError(t, err)
	second, err := crypto.encrypt("person@example.com")
	require.NoError(t, err)
	require.NotEqual(t, first, second, "AES-GCM must use a fresh nonce")
	require.NotContains(t, string(first), "person@example.com")

	decrypted, err := crypto.decrypt(first)
	require.NoError(t, err)
	require.Equal(t, "person@example.com", decrypted)
	require.True(t, bytes.Equal(crypto.lookup("person@example.com"), crypto.lookup("person@example.com")))
	require.False(t, bytes.Equal(crypto.lookup("person@example.com"), crypto.lookup("other@example.com")))
}

func TestEmailCryptoRejectsTamperedCiphertext(t *testing.T) {
	t.Parallel()

	crypto, err := newEmailCrypto("encryption secret", "lookup secret")
	require.NoError(t, err)
	ciphertext, err := crypto.encrypt("person@example.com")
	require.NoError(t, err)
	ciphertext[len(ciphertext)-1] ^= 1

	_, err = crypto.decrypt(ciphertext)
	require.Error(t, err)
}
