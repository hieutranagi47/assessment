package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestRestoreUserAllowsAnEmailAbsentFromStorage(t *testing.T) {
	t.Parallel()

	user, err := RestoreUser(
		uuid.New(),
		"",
		"Privacy First",
		"password-hash",
		[2]string{},
		1,
		StatusActive,
		time.Now(),
		time.Now(),
	)

	require.NoError(t, err)
	require.Empty(t, user.Email())
}
