package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestNewDealershipUserAcceptsTechnicianRole(t *testing.T) {
	now := time.Date(2026, 8, 28, 9, 0, 0, 0, time.UTC)

	user, err := NewDealershipUser(
		uuid.New(),
		uuid.New(),
		uuid.New(),
		"Alex Kim",
		"alex@example.com",
		"technician",
		now,
	)

	require.NoError(t, err)
	require.Equal(t, "technician", user.Role())
}
