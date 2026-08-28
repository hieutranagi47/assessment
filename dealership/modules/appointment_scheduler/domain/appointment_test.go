package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestAppointmentLifecyclePreservesPlannedEnd(t *testing.T) {
	start := time.Date(2026, 8, 28, 8, 0, 0, 0, time.UTC)
	appointment, err := NewAppointment(uuid.New(), start, start.Add(time.Hour))
	require.NoError(t, err)

	appointment, err = appointment.CheckIn(start.Add(5 * time.Minute))
	require.NoError(t, err)
	appointment, err = appointment.Start(start.Add(10 * time.Minute))
	require.NoError(t, err)
	appointment, err = appointment.Complete(start.Add(45 * time.Minute))
	require.NoError(t, err)
	require.Equal(t, AppointmentCompleted, appointment.Status())
	require.Equal(t, start.Add(time.Hour), appointment.EndsAt())
	require.Equal(t, start.Add(45*time.Minute), *appointment.ActualEndsAt())
}

func TestAppointmentRejectsInvalidTransition(t *testing.T) {
	start := time.Now().UTC()
	appointment, err := NewAppointment(uuid.New(), start, start.Add(time.Hour))
	require.NoError(t, err)
	_, err = appointment.Complete(start.Add(time.Hour))
	require.ErrorIs(t, err, ErrInvalidStatusTransition)
}
