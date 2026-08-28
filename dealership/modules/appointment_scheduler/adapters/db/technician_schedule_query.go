package db

import (
	"context"
	"errors"
	"time"

	"assessment/modules/appointment_scheduler/adapters/db/dbmodels"
	"assessment/modules/appointment_scheduler/app"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func (r *DealershipRepository) CanReadTechnicianSchedules(ctx context.Context, authUserID, dealershipID uuid.UUID) (bool, error) {
	return r.queries.CanReadTechnicianSchedules(ctx, dbmodels.CanReadTechnicianSchedulesParams{
		AuthUserID:   toPGUUID(authUserID),
		DealershipID: toPGUUID(dealershipID),
	})
}

func (r *DealershipRepository) GetActiveTechnicianScheduleDealership(ctx context.Context, dealershipID uuid.UUID) (app.TechnicianScheduleDealership, error) {
	row, err := r.queries.GetActiveTechnicianScheduleDealership(ctx, toPGUUID(dealershipID))
	if errors.Is(err, pgx.ErrNoRows) {
		return app.TechnicianScheduleDealership{}, app.ErrTechnicianScheduleDealershipNotFound
	}
	if err != nil {
		return app.TechnicianScheduleDealership{}, err
	}
	return app.TechnicianScheduleDealership{ID: fromPGUUID(row.DealershipID), Timezone: row.Timezone}, nil
}

func (r *DealershipRepository) ListActiveTechniciansForSchedule(ctx context.Context, dealershipID uuid.UUID, technicianID *uuid.UUID) ([]app.TechnicianScheduleTechnician, error) {
	rows, err := r.queries.ListActiveTechniciansForSchedule(ctx, dbmodels.ListActiveTechniciansForScheduleParams{
		DealershipID: toPGUUID(dealershipID),
		TechnicianID: nullablePGUUID(technicianID),
	})
	if err != nil {
		return nil, err
	}
	items := make([]app.TechnicianScheduleTechnician, 0, len(rows))
	for _, row := range rows {
		items = append(items, app.TechnicianScheduleTechnician{TechnicianID: fromPGUUID(row.TechnicianID), UserID: fromPGUUID(row.UserID), Name: row.Name})
	}
	return items, nil
}

func (r *DealershipRepository) ListTechnicianScheduleShifts(ctx context.Context, dealershipID uuid.UUID, technicianID *uuid.UUID, dayOfWeek int) ([]app.TechnicianScheduleShift, error) {
	rows, err := r.queries.ListTechnicianScheduleShifts(ctx, dbmodels.ListTechnicianScheduleShiftsParams{
		DealershipID: toPGUUID(dealershipID),
		DayOfWeek:    int16(dayOfWeek),
		TechnicianID: nullablePGUUID(technicianID),
	})
	if err != nil {
		return nil, err
	}
	items := make([]app.TechnicianScheduleShift, 0, len(rows))
	for _, row := range rows {
		items = append(items, app.TechnicianScheduleShift{TechnicianID: fromPGUUID(row.TechnicianID), StartsAt: time.Duration(row.StartsAt.Microseconds) * time.Microsecond, EndsAt: time.Duration(row.EndsAt.Microseconds) * time.Microsecond})
	}
	return items, nil
}

func (r *DealershipRepository) ListTechnicianScheduleAppointments(ctx context.Context, dealershipID uuid.UUID, technicianID *uuid.UUID, periodStartsAt, periodEndsAt time.Time) ([]app.TechnicianScheduleAppointment, error) {
	rows, err := r.queries.ListTechnicianScheduleAppointments(ctx, dbmodels.ListTechnicianScheduleAppointmentsParams{
		DealershipID:   toPGUUID(dealershipID),
		PeriodStartsAt: periodStartsAt,
		PeriodEndsAt:   periodEndsAt,
		TechnicianID:   nullablePGUUID(technicianID),
	})
	if err != nil {
		return nil, err
	}
	items := make([]app.TechnicianScheduleAppointment, 0, len(rows))
	for _, row := range rows {
		items = append(items, app.TechnicianScheduleAppointment{TechnicianID: fromPGUUID(row.TechnicianID), AppointmentID: fromPGUUID(row.AppointmentID), ReferenceCode: row.ReferenceCode, StartsAt: row.StartsAt, EndsAt: row.EndsAt, Status: row.Status, ServiceTypeName: row.ServiceTypeName, ServiceBayID: fromPGUUID(row.ServiceBayID), ServiceBayCode: row.ServiceBayCode})
	}
	return items, nil
}

func (r *DealershipRepository) ListTechnicianScheduleTimeOff(ctx context.Context, dealershipID uuid.UUID, technicianID *uuid.UUID, periodStartsAt, periodEndsAt time.Time) ([]app.TechnicianScheduleTimeOff, error) {
	rows, err := r.queries.ListTechnicianScheduleTimeOff(ctx, dbmodels.ListTechnicianScheduleTimeOffParams{
		DealershipID:   toPGUUID(dealershipID),
		PeriodStartsAt: periodStartsAt,
		PeriodEndsAt:   periodEndsAt,
		TechnicianID:   nullablePGUUID(technicianID),
	})
	if err != nil {
		return nil, err
	}
	items := make([]app.TechnicianScheduleTimeOff, 0, len(rows))
	for _, row := range rows {
		items = append(items, app.TechnicianScheduleTimeOff{TechnicianID: fromPGUUID(row.TechnicianID), StartsAt: row.StartsAt, EndsAt: row.EndsAt})
	}
	return items, nil
}

func nullablePGUUID(value *uuid.UUID) pgtype.UUID {
	if value == nil {
		return pgtype.UUID{}
	}
	return toPGUUID(*value)
}
