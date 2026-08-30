package app

import (
	"context"
	"testing"
	"time"

	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type dealershipAppointmentsRepositoryStub struct {
	allowed      bool
	dealership   DealershipAppointmentsDealership
	appointments []DealershipAppointment
	periodStart  time.Time
	periodEnd    time.Time
}

func (s *dealershipAppointmentsRepositoryStub) CanReadDealershipAppointments(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return s.allowed, nil
}

func (s *dealershipAppointmentsRepositoryStub) GetActiveDealershipForAppointments(context.Context, uuid.UUID) (DealershipAppointmentsDealership, error) {
	return s.dealership, nil
}

func (s *dealershipAppointmentsRepositoryStub) ListDealershipAppointments(_ context.Context, _ uuid.UUID, periodStart, periodEnd time.Time) ([]DealershipAppointment, error) {
	s.periodStart = periodStart
	s.periodEnd = periodEnd
	return s.appointments, nil
}

func TestDealershipAppointmentsQueryUsesDealershipLocalDate(t *testing.T) {
	dealershipID := uuid.New()
	repository := &dealershipAppointmentsRepositoryStub{
		allowed:    true,
		dealership: DealershipAppointmentsDealership{ID: dealershipID, Timezone: "Asia/Ho_Chi_Minh"},
		appointments: []DealershipAppointment{{
			AppointmentID: uuid.New(),
			StartsAt:      time.Date(2026, 9, 15, 18, 0, 0, 0, time.UTC),
			EndsAt:        time.Date(2026, 9, 15, 19, 0, 0, 0, time.UTC),
		}},
	}

	result, err := NewDealershipAppointmentsQuery(repository).List(context.Background(), ListDealershipAppointmentsInput{
		ActorUserID:  uuid.New(),
		DealershipID: dealershipID,
		Date:         "2026-09-16",
	})

	require.NoError(t, err)
	require.Equal(t, time.Date(2026, 9, 15, 17, 0, 0, 0, time.UTC), repository.periodStart)
	require.Equal(t, time.Date(2026, 9, 16, 17, 0, 0, 0, time.UTC), repository.periodEnd)
	require.Equal(t, "Asia/Ho_Chi_Minh", result.Timezone)
	require.Len(t, result.Appointments, 1)
}

func TestDealershipAppointmentsQueryValidatesDateAndAccess(t *testing.T) {
	dealershipID := uuid.New()
	query := NewDealershipAppointmentsQuery(&dealershipAppointmentsRepositoryStub{allowed: false})

	_, err := query.List(context.Background(), ListDealershipAppointmentsInput{
		ActorUserID:  uuid.New(),
		DealershipID: dealershipID,
		Date:         "2026-09-16T00:00:00Z",
	})
	var structured common.Error
	require.ErrorAs(t, err, &structured)
	require.Equal(t, "invalid_date", structured.ErrorSlug)

	_, err = query.List(context.Background(), ListDealershipAppointmentsInput{
		ActorUserID:  uuid.New(),
		DealershipID: dealershipID,
		Date:         "2026-09-16",
	})
	require.ErrorAs(t, err, &structured)
	require.Equal(t, "dealership_appointments_access_forbidden", structured.ErrorSlug)
}
