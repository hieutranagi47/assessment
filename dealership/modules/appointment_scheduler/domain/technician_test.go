package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestTechnicianLifecycleNormalizesDetails(t *testing.T) {
	now := time.Date(2026, 1, 2, 3, 4, 5, 0, time.FixedZone("ICT", 7*60*60))
	email := " TECHNICIAN@example.com "
	technician, err := NewTechnician(uuid.New(), uuid.New(), " Ada ", " 00 84-900.000.000 ", &email, true, now)
	require.NoError(t, err)
	require.Equal(t, "Ada", technician.Name())
	require.Equal(t, "+84900000000", technician.Phone())
	require.Equal(t, "technician@example.com", *technician.Email())

	updated, err := technician.Update("Grace", "+84911111111", nil, false, now.Add(time.Hour))
	require.NoError(t, err)
	require.False(t, updated.IsActive())
	require.Nil(t, updated.Email())
	require.Equal(t, now.Add(time.Hour).UTC(), updated.UpdatedAt())

	rehydrated, err := RehydrateTechnician(technician.ID(), technician.UserID(), "Ada", "+84900000000", nil, true, now, now.Add(2*time.Hour))
	require.NoError(t, err)
	require.Equal(t, now.Add(2*time.Hour).UTC(), rehydrated.UpdatedAt())
}

func TestTechnicianRejectsInvalidDetails(t *testing.T) {
	validID := uuid.New()
	_, err := NewTechnician(uuid.Nil, validID, "Ada", "+84900000000", nil, true, time.Now())
	require.ErrorIs(t, err, ErrTechnicianIDRequired)
	_, err = NewTechnician(validID, uuid.Nil, "Ada", "+84900000000", nil, true, time.Now())
	require.ErrorIs(t, err, ErrTechnicianUserIDRequired)
	_, err = NewTechnician(validID, validID, "", "+84900000000", nil, true, time.Now())
	require.ErrorIs(t, err, ErrTechnicianNameRequired)
	_, err = NewTechnician(validID, validID, "Ada", "0900000000", nil, true, time.Now())
	require.ErrorIs(t, err, ErrTechnicianPhoneInvalid)
	invalidEmail := "not-an-email"
	_, err = NewTechnician(validID, validID, "Ada", "+84900000000", &invalidEmail, true, time.Now())
	require.ErrorIs(t, err, ErrTechnicianEmailInvalid)
}
