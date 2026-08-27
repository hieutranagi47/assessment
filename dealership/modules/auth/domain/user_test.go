package domain

import (
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestUserChangePasswordKeepsHistoryAndRevokesTokens(t *testing.T) {
	now := time.Date(2026, 8, 12, 0, 0, 0, 0, time.UTC)
	user, err := NewUser(uuid.New(), "person@example.com", "Person", "one", now)
	require.NoError(t, err)

	require.NoError(t, user.ChangePassword("two", func(string) bool { return false }, true, now.Add(time.Hour)))
	require.Equal(t, 2, user.TokenVersion())
	require.Equal(t, [2]string{"one", ""}, user.PreviousPasswordHashes())

	err = user.ChangePassword("three", func(hash string) bool { return hash == "one" }, false, now.Add(2*time.Hour))
	require.ErrorIs(t, err, ErrPasswordReused)
}

func TestUserRejectsInvalidState(t *testing.T) {
	_, err := NewUser(uuid.New(), "not an email", "", "hash", time.Now())
	require.ErrorIs(t, err, ErrInvalidEmail)

	user, err := NewUser(uuid.New(), "person@example.com", "", "hash", time.Now())
	require.NoError(t, err)
	require.ErrorIs(t, user.ChangeStatus("pending", time.Now()), ErrInvalidUserStatus)
	require.True(t, errors.Is(user.UpdateFullName(" ", time.Now()), ErrInvalidFullName))
}
