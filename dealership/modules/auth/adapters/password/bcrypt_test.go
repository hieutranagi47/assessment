package password

import (
	"errors"
	"testing"

	"assessment/modules/auth/domain"

	"github.com/stretchr/testify/require"
)

func TestBcryptHasher(t *testing.T) {
	hasher := BcryptHasher{}

	hash, err := hasher.Hash("Password1@")
	require.NoError(t, err)
	require.NotEqual(t, "Password1@", hash)
	require.True(t, hasher.Matches(hash, "Password1@"))
	require.False(t, hasher.Matches(hash, "other password"))
}

func TestBcryptHasherRejectsBlankPassword(t *testing.T) {
	_, err := (BcryptHasher{}).Hash(" \t ")
	require.True(t, errors.Is(err, domain.ErrInvalidPassword))
}
