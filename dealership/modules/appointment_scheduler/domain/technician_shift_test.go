package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestNewTechnicianShiftRejectsInvalidWeeklyInterval(t *testing.T) {
	validID := uuid.New()
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

	for _, testCase := range []struct {
		name     string
		day      int
		startsAt time.Duration
		endsAt   time.Duration
		expected error
	}{
		{"weekday below range", 0, 8 * time.Hour, 17 * time.Hour, ErrInvalidShiftWeekday},
		{"weekday above range", 8, 8 * time.Hour, 17 * time.Hour, ErrInvalidShiftWeekday},
		{"end before start", 1, 17 * time.Hour, 8 * time.Hour, ErrInvalidShiftHours},
		{"equal clocks", 1, 8 * time.Hour, 8 * time.Hour, ErrInvalidShiftHours},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			_, err := NewTechnicianShift(validID, validID, testCase.day, testCase.startsAt, testCase.endsAt, now)
			require.ErrorIs(t, err, testCase.expected)
		})
	}
}

func TestTechnicianShiftUpdatePreservesIdentityAndCreationTime(t *testing.T) {
	createdAt := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	shift, err := NewTechnicianShift(uuid.New(), uuid.New(), 1, 8*time.Hour, 17*time.Hour, createdAt)
	require.NoError(t, err)

	updatedAt := createdAt.Add(time.Hour)
	updated, err := shift.Update(2, 9*time.Hour, 18*time.Hour, updatedAt)
	require.NoError(t, err)
	require.Equal(t, shift.ID(), updated.ID())
	require.Equal(t, shift.TechnicianID(), updated.TechnicianID())
	require.Equal(t, createdAt, updated.CreatedAt())
	require.Equal(t, updatedAt, updated.UpdatedAt())
}
