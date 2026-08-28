package app

import (
	"context"
	"testing"
	"time"

	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type technicianScheduleRepositoryStub struct {
	allowed      bool
	dealership   TechnicianScheduleDealership
	technicians  []TechnicianScheduleTechnician
	shifts       []TechnicianScheduleShift
	appointments []TechnicianScheduleAppointment
	timeOff      []TechnicianScheduleTimeOff
}

func (s technicianScheduleRepositoryStub) CanReadTechnicianSchedules(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return s.allowed, nil
}

func (s technicianScheduleRepositoryStub) GetActiveTechnicianScheduleDealership(context.Context, uuid.UUID) (TechnicianScheduleDealership, error) {
	return s.dealership, nil
}

func (s technicianScheduleRepositoryStub) ListActiveTechniciansForSchedule(_ context.Context, _ uuid.UUID, technicianID *uuid.UUID) ([]TechnicianScheduleTechnician, error) {
	if technicianID == nil {
		return s.technicians, nil
	}
	items := make([]TechnicianScheduleTechnician, 0, 1)
	for _, technician := range s.technicians {
		if technician.TechnicianID == *technicianID {
			items = append(items, technician)
		}
	}
	return items, nil
}

func (s technicianScheduleRepositoryStub) ListTechnicianScheduleShifts(_ context.Context, _ uuid.UUID, _ *uuid.UUID, _ int) ([]TechnicianScheduleShift, error) {
	return s.shifts, nil
}

func (s technicianScheduleRepositoryStub) ListTechnicianScheduleAppointments(_ context.Context, _ uuid.UUID, _ *uuid.UUID, _, _ time.Time) ([]TechnicianScheduleAppointment, error) {
	return s.appointments, nil
}

func (s technicianScheduleRepositoryStub) ListTechnicianScheduleTimeOff(_ context.Context, _ uuid.UUID, _ *uuid.UUID, _, _ time.Time) ([]TechnicianScheduleTimeOff, error) {
	return s.timeOff, nil
}

func TestTechnicianScheduleQueryListsCalendarsAndSortsOccupiedSlots(t *testing.T) {
	dealershipID := uuid.New()
	firstTechnicianID := uuid.New()
	secondTechnicianID := uuid.New()
	appointmentID := uuid.New()
	query := NewTechnicianScheduleQuery(technicianScheduleRepositoryStub{
		allowed:    true,
		dealership: TechnicianScheduleDealership{ID: dealershipID, Timezone: "Asia/Ho_Chi_Minh"},
		technicians: []TechnicianScheduleTechnician{
			{TechnicianID: firstTechnicianID, UserID: uuid.New(), Name: "First"},
			{TechnicianID: secondTechnicianID, UserID: uuid.New(), Name: "Second"},
		},
		shifts:       []TechnicianScheduleShift{{TechnicianID: firstTechnicianID, StartsAt: 8 * time.Hour, EndsAt: 16 * time.Hour}},
		appointments: []TechnicianScheduleAppointment{{TechnicianID: firstTechnicianID, AppointmentID: appointmentID, ReferenceCode: "APT-001", StartsAt: time.Date(2026, 8, 28, 3, 0, 0, 0, time.UTC), EndsAt: time.Date(2026, 8, 28, 4, 0, 0, 0, time.UTC), Status: "requested", ServiceTypeName: "Oil change", ServiceBayID: uuid.New(), ServiceBayCode: "BAY-01"}},
		timeOff:      []TechnicianScheduleTimeOff{{TechnicianID: firstTechnicianID, StartsAt: time.Date(2026, 8, 28, 1, 0, 0, 0, time.UTC), EndsAt: time.Date(2026, 8, 28, 2, 0, 0, 0, time.UTC)}},
	})

	result, err := query.List(context.Background(), ListTechnicianSchedulesInput{ActorUserID: uuid.New(), DealershipID: dealershipID, Date: "2026-08-28"})
	require.NoError(t, err)
	require.Equal(t, time.Date(2026, 8, 27, 17, 0, 0, 0, time.UTC), result.PeriodStartsAt)
	require.Equal(t, time.Date(2026, 8, 28, 17, 0, 0, 0, time.UTC), result.PeriodEndsAt)
	require.Len(t, result.Technicians, 2)
	require.Empty(t, result.Technicians[1].Shifts)
	require.Empty(t, result.Technicians[1].OccupiedSlots)
	require.Equal(t, "time_off", result.Technicians[0].OccupiedSlots[0].Kind)
	require.Equal(t, "appointment", result.Technicians[0].OccupiedSlots[1].Kind)
	require.Equal(t, appointmentID, *result.Technicians[0].OccupiedSlots[1].AppointmentID)
	require.Equal(t, time.Date(2026, 8, 28, 1, 0, 0, 0, time.UTC), result.Technicians[0].Shifts[0].StartsAt)
}

func TestTechnicianScheduleQueryUsesLocalMidnightAcrossDST(t *testing.T) {
	dealershipID := uuid.New()
	technicianID := uuid.New()
	query := NewTechnicianScheduleQuery(technicianScheduleRepositoryStub{
		allowed:     true,
		dealership:  TechnicianScheduleDealership{ID: dealershipID, Timezone: "America/New_York"},
		technicians: []TechnicianScheduleTechnician{{TechnicianID: technicianID, UserID: uuid.New(), Name: "DST technician"}},
		shifts:      []TechnicianScheduleShift{{TechnicianID: technicianID, StartsAt: 9 * time.Hour, EndsAt: 17 * time.Hour}},
	})

	result, err := query.List(context.Background(), ListTechnicianSchedulesInput{ActorUserID: uuid.New(), DealershipID: dealershipID, Date: "2026-03-08", Include: []string{"shifts"}})
	require.NoError(t, err)
	require.Equal(t, 23*time.Hour, result.PeriodEndsAt.Sub(result.PeriodStartsAt))
	require.Equal(t, time.Date(2026, 3, 8, 5, 0, 0, 0, time.UTC), result.PeriodStartsAt)
	require.Equal(t, time.Date(2026, 3, 9, 4, 0, 0, 0, time.UTC), result.PeriodEndsAt)
	require.Equal(t, time.Date(2026, 3, 8, 13, 0, 0, 0, time.UTC), result.Technicians[0].Shifts[0].StartsAt)
}

func TestTechnicianScheduleQueryValidatesAndScopesAccess(t *testing.T) {
	dealershipID := uuid.New()
	query := NewTechnicianScheduleQuery(technicianScheduleRepositoryStub{allowed: false})

	_, err := query.List(context.Background(), ListTechnicianSchedulesInput{ActorUserID: uuid.New(), DealershipID: dealershipID, Date: "invalid"})
	require.ErrorAs(t, err, new(common.Error))
	var structured common.Error
	require.ErrorAs(t, err, &structured)
	require.Equal(t, "invalid_date", structured.ErrorSlug)

	_, err = query.List(context.Background(), ListTechnicianSchedulesInput{ActorUserID: uuid.New(), DealershipID: dealershipID, Date: "2026-08-28"})
	require.ErrorAs(t, err, &structured)
	require.Equal(t, "technician_schedule_access_forbidden", structured.ErrorSlug)

	missingTechnicianID := uuid.New()
	query = NewTechnicianScheduleQuery(technicianScheduleRepositoryStub{allowed: true, dealership: TechnicianScheduleDealership{ID: dealershipID, Timezone: "UTC"}})
	_, err = query.List(context.Background(), ListTechnicianSchedulesInput{ActorUserID: uuid.New(), DealershipID: dealershipID, Date: "2026-08-28", TechnicianID: &missingTechnicianID})
	require.ErrorAs(t, err, &structured)
	require.Equal(t, "technician_not_found", structured.ErrorSlug)
}
