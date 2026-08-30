package db

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"assessment/modules/appointment_scheduler/adapters/db/dbmodels"
	"assessment/modules/appointment_scheduler/app"
	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
)

// ScheduleAppointment performs every availability check and the capacity
// writes in one serializable PostgreSQL transaction. The exclusion constraint
// remains the authoritative concurrency guard.
func (r *DealershipRepository) ScheduleAppointment(ctx context.Context, record app.ScheduleAppointmentRecord) error {
	return common.UpdateInSerializableTx(ctx, r.database, func(ctx context.Context, tx pgx.Tx) error {
		queries := r.queries.WithTx(tx)
		timezone, err := queries.GetActiveDealershipTimezone(ctx, toPGUUID(record.DealershipID))
		if errors.Is(err, pgx.ErrNoRows) {
			return common.NewNotFoundError("not_found", "dealership not found")
		}
		if err != nil {
			return err
		}

		duration, err := queries.GetActiveServiceTypeDuration(ctx, dbmodels.GetActiveServiceTypeDurationParams{
			ServiceTypeID: toPGUUID(record.ServiceTypeID),
			DealershipID:  toPGUUID(record.DealershipID),
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return common.NewNotFoundError("not_found", "service type not found")
		}
		if err != nil {
			return err
		}
		minDuration := int(duration.MinDurationMinutes)
		maxDuration := int(duration.MaxDurationMinutes)
		if record.PlannedDurationMinutes == 0 {
			record.PlannedDurationMinutes = maxDuration
		}
		if record.PlannedDurationMinutes < minDuration || record.PlannedDurationMinutes > maxDuration {
			return common.NewInvalidInputError("validation_error", "planned duration must be between %d and %d minutes", minDuration, maxDuration)
		}
		record.EndsAt = record.StartsAt.Add(time.Duration(record.PlannedDurationMinutes) * time.Minute)

		valid, err := queries.CustomerVehicleBelongsToDealership(ctx, dbmodels.CustomerVehicleBelongsToDealershipParams{
			VehicleID:    toPGUUID(record.VehicleID),
			CustomerID:   toPGUUID(record.CustomerID),
			DealershipID: toPGUUID(record.DealershipID),
		})
		if err != nil {
			return err
		}
		if !valid {
			return common.Error{HttpErrorCode: 422, PublicError: "vehicle does not belong to the customer in this dealership", ErrorSlug: "invalid_customer_vehicle"}
		}

		// A single local-day interval and one operating-hours row are required;
		// unsupported cross-boundary bookings are deliberately rejected.
		valid, err = queries.IsWithinDealershipOperatingHours(ctx, dbmodels.IsWithinDealershipOperatingHoursParams{
			DealershipID: toPGUUID(record.DealershipID),
			Timezone:     timezone,
			StartsAt:     record.StartsAt,
			EndsAt:       record.EndsAt,
		})
		if err != nil {
			return err
		}
		if !valid {
			return common.Error{HttpErrorCode: 422, PublicError: "appointment is outside dealership operating hours", ErrorSlug: "operating_hours_violation"}
		}

		valid, err = queries.IsCompatibleTechnician(ctx, dbmodels.IsCompatibleTechnicianParams{
			TechnicianID:  toPGUUID(record.TechnicianID),
			DealershipID:  toPGUUID(record.DealershipID),
			ServiceTypeID: toPGUUID(record.ServiceTypeID),
		})
		if err != nil {
			return err
		}
		if !valid {
			return common.Error{HttpErrorCode: 422, PublicError: "technician is inactive or lacks required skills", ErrorSlug: "incompatible_technician"}
		}

		valid, err = queries.IsCompatibleServiceBay(ctx, dbmodels.IsCompatibleServiceBayParams{
			ServiceBayID:  toPGUUID(record.ServiceBayID),
			DealershipID:  toPGUUID(record.DealershipID),
			ServiceTypeID: toPGUUID(record.ServiceTypeID),
		})
		if err != nil {
			return err
		}
		if !valid {
			return common.Error{HttpErrorCode: 422, PublicError: "service bay is inactive or incompatible", ErrorSlug: "incompatible_service_bay"}
		}

		available, err := queries.IsTechnicianAvailableForAppointment(ctx, dbmodels.IsTechnicianAvailableForAppointmentParams{
			TechnicianID: toPGUUID(record.TechnicianID),
			Timezone:     timezone,
			StartsAt:     record.StartsAt,
			EndsAt:       record.EndsAt,
		})
		if err != nil {
			return err
		}
		if available == nil || !*available {
			return common.Error{HttpErrorCode: 422, PublicError: "technician shift or time off prevents this appointment", ErrorSlug: "technician_schedule_violation"}
		}

		plannedDurationMinutes := int32(record.PlannedDurationMinutes)
		err = queries.CreateScheduledAppointment(ctx, dbmodels.CreateScheduledAppointmentParams{
			AppointmentID:          toPGUUID(record.AppointmentID),
			ReferenceCode:          record.ReferenceCode,
			CustomerID:             toPGUUID(record.CustomerID),
			VehicleID:              toPGUUID(record.VehicleID),
			DealershipID:           toPGUUID(record.DealershipID),
			ServiceTypeID:          toPGUUID(record.ServiceTypeID),
			TechnicianID:           toPGUUID(record.TechnicianID),
			ServiceBayID:           toPGUUID(record.ServiceBayID),
			StartsAt:               record.StartsAt,
			EndsAt:                 record.EndsAt,
			PlannedDurationMinutes: &plannedDurationMinutes,
			Notes:                  record.Notes,
			CreatedByUserID:        toPGUUID(record.CreatedByUserID),
			CreatedAt:              record.CreatedAt,
			UpdatedAt:              record.UpdatedAt,
		})
		if err != nil {
			return appointmentWriteError(err)
		}
		for _, resource := range []struct {
			kind string
			id   uuid.UUID
		}{{"technician", record.TechnicianID}, {"service_bay", record.ServiceBayID}} {
			err = queries.CreateAppointmentResourceReservation(ctx, dbmodels.CreateAppointmentResourceReservationParams{
				AppointmentResourceReservationID: toPGUUID(uuid.New()), AppointmentID: toPGUUID(record.AppointmentID), ResourceType: resource.kind, ResourceID: toPGUUID(resource.id), ReservedStartsAt: record.StartsAt, ReservedEndsAt: record.EndsAt, Status: "requested", AssignedAt: record.CreatedAt, AssignedByUserID: toPGUUID(record.CreatedByUserID),
			})
			if err != nil {
				return appointmentWriteError(err)
			}
		}
		after, err := json.Marshal(map[string]any{"status": "requested", "starts_at": record.StartsAt, "ends_at": record.EndsAt})
		if err != nil {
			return fmt.Errorf("marshal appointment audit event: %w", err)
		}
		return queries.CreateAppointmentAuditEvents(ctx, dbmodels.CreateAppointmentAuditEventsParams{AppointmentAuditEventID: toPGUUID(uuid.New()), AppointmentID: toPGUUID(record.AppointmentID), ActorUserID: toPGUUID(record.CreatedByUserID), EventType: "created", AfterData: after, OccurredAt: record.CreatedAt})
	})
}

func appointmentWriteError(err error) error {
	var pgError *pgconn.PgError
	if errors.As(err, &pgError) && (pgError.Code == "23P01" || pgError.ConstraintName == "appointment_resource_reservations_no_overlap") {
		return app.ErrAppointmentUnavailable
	}
	return err
}

// TransitionAppointment locks the dealership-scoped row, applies one allowed
// lifecycle transition, and records the before/after payload before commit.
func (r *DealershipRepository) TransitionAppointment(ctx context.Context, transition app.AppointmentTransition) error {
	return common.UpdateInSerializableTx(ctx, r.database, func(ctx context.Context, tx pgx.Tx) error {
		queries := r.queries.WithTx(tx)
		appointment, err := queries.GetAppointmentForTransition(ctx, dbmodels.GetAppointmentForTransitionParams{
			AppointmentID: toPGUUID(transition.AppointmentID),
			DealershipID:  toPGUUID(transition.DealershipID),
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return common.NewNotFoundError("not_found", "appointment not found")
		}
		if err != nil {
			return err
		}
		if transition.From != "" && appointment.Status != string(transition.From) {
			return common.NewConflictError("invalid_state_transition", "the appointment is no longer in the expected state")
		}
		if transition.To == "cancelled" && appointment.Status != "requested" && appointment.Status != "checked_in" && appointment.Status != "in_progress" {
			return common.NewConflictError("invalid_state_transition", "the appointment cannot be cancelled from its current state")
		}

		before, err := json.Marshal(map[string]any{"status": appointment.Status, "notes": appointment.Notes})
		if err != nil {
			return fmt.Errorf("marshal appointment audit before state: %w", err)
		}
		updatedNotes := appointment.Notes
		if transition.Note != nil {
			updatedNotes = transition.Note
		}
		actualEndsAt := transition.ActualEndsAt
		if transition.To == "completed" {
			if actualEndsAt == nil {
				actualEndsAt = &transition.OccurredAt
			}
			checkedInAt, err := queries.GetAppointmentCheckedInAt(ctx, toPGUUID(transition.AppointmentID))
			if err != nil {
				return err
			}
			if !checkedInAt.Valid || actualEndsAt.Before(checkedInAt.Time) || actualEndsAt.After(appointment.EndsAt) {
				return common.NewInvalidInputError("validation_error", "actual_ends_at must be between check-in and the planned end")
			}
		}

		switch transition.To {
		case "checked_in":
			err = queries.CheckInAppointment(ctx, dbmodels.CheckInAppointmentParams{OccurredAt: pgTimestamptz(transition.OccurredAt), Notes: updatedNotes, AppointmentID: toPGUUID(transition.AppointmentID)})
		case "in_progress":
			err = queries.StartAppointment(ctx, dbmodels.StartAppointmentParams{OccurredAt: pgTimestamptz(transition.OccurredAt), Notes: updatedNotes, AppointmentID: toPGUUID(transition.AppointmentID)})
		case "completed":
			err = queries.CompleteAppointment(ctx, dbmodels.CompleteAppointmentParams{OccurredAt: pgTimestamptz(transition.OccurredAt), ActualEndsAt: pgTimestamptz(*actualEndsAt), Notes: updatedNotes, AppointmentID: toPGUUID(transition.AppointmentID)})
		case "cancelled":
			err = queries.CancelAppointment(ctx, dbmodels.CancelAppointmentParams{OccurredAt: pgTimestamptz(transition.OccurredAt), ActorUserID: toPGUUID(transition.ActorUserID), CancellationReason: transition.CancellationReason, Notes: updatedNotes, AppointmentID: toPGUUID(transition.AppointmentID)})
		default:
			return common.NewConflictError("invalid_state_transition", "unsupported appointment state")
		}
		if err != nil {
			return err
		}
		if transition.To == "completed" || transition.To == "cancelled" {
			_, err = queries.ReleaseAppointmentResourceReservations(ctx, dbmodels.ReleaseAppointmentResourceReservationsParams{ReleasedAt: pgTimestamptz(transition.OccurredAt), Status: string(transition.To), AppointmentID: toPGUUID(transition.AppointmentID)})
			if err != nil {
				return err
			}
		}
		after, err := json.Marshal(map[string]any{"status": transition.To, "notes": updatedNotes, "actual_ends_at": actualEndsAt, "cancellation_reason": transition.CancellationReason})
		if err != nil {
			return fmt.Errorf("marshal appointment audit after state: %w", err)
		}
		return queries.CreateAppointmentAuditEvents(ctx, dbmodels.CreateAppointmentAuditEventsParams{AppointmentAuditEventID: toPGUUID(uuid.New()), AppointmentID: toPGUUID(transition.AppointmentID), ActorUserID: toPGUUID(transition.ActorUserID), EventType: "status_changed", BeforeData: before, AfterData: after, OccurredAt: transition.OccurredAt})
	})
}

func pgTimestamptz(value time.Time) pgtype.Timestamptz {
	return pgtype.Timestamptz{Time: value.UTC(), Valid: true}
}

var _ app.DealershipAppointmentsRepository = (*DealershipRepository)(nil)

func (r *DealershipRepository) CanReadDealershipAppointments(ctx context.Context, authUserID, dealershipID uuid.UUID) (bool, error) {
	return r.queries.CanReadDealershipAppointments(ctx, dbmodels.CanReadDealershipAppointmentsParams{
		AuthUserID:   toPGUUID(authUserID),
		DealershipID: toPGUUID(dealershipID),
	})
}

func (r *DealershipRepository) GetActiveDealershipForAppointments(ctx context.Context, dealershipID uuid.UUID) (app.DealershipAppointmentsDealership, error) {
	row, err := r.queries.GetActiveDealershipForAppointments(ctx, toPGUUID(dealershipID))
	if errors.Is(err, pgx.ErrNoRows) {
		return app.DealershipAppointmentsDealership{}, app.ErrDealershipAppointmentsDealershipNotFound
	}
	if err != nil {
		return app.DealershipAppointmentsDealership{}, err
	}
	return app.DealershipAppointmentsDealership{
		ID:       fromPGUUID(row.DealershipID),
		Timezone: row.Timezone,
	}, nil
}

func (r *DealershipRepository) ListDealershipAppointments(ctx context.Context, dealershipID uuid.UUID, periodStartsAt, periodEndsAt time.Time) ([]app.DealershipAppointment, error) {
	rows, err := r.queries.ListDealershipAppointments(ctx, dbmodels.ListDealershipAppointmentsParams{
		DealershipID:   toPGUUID(dealershipID),
		PeriodStartsAt: periodStartsAt.UTC(),
		PeriodEndsAt:   periodEndsAt.UTC(),
	})
	if err != nil {
		return nil, err
	}
	items := make([]app.DealershipAppointment, 0, len(rows))
	for _, row := range rows {
		var actualEndsAt *time.Time
		if row.ActualEndsAt.Valid {
			value := row.ActualEndsAt.Time.UTC()
			actualEndsAt = &value
		}
		plannedDurationMinutes := 0
		if row.PlannedDurationMinutes != nil {
			plannedDurationMinutes = int(*row.PlannedDurationMinutes)
		}
		items = append(items, app.DealershipAppointment{
			AppointmentID:          fromPGUUID(row.AppointmentID),
			ReferenceCode:          row.ReferenceCode,
			CustomerID:             fromPGUUID(row.CustomerID),
			VehicleID:              fromPGUUID(row.VehicleID),
			DealershipID:           fromPGUUID(row.DealershipID),
			ServiceTypeID:          fromPGUUID(row.ServiceTypeID),
			TechnicianID:           fromPGUUID(row.TechnicianID),
			ServiceBayID:           fromPGUUID(row.ServiceBayID),
			StartsAt:               row.StartsAt,
			EndsAt:                 row.EndsAt,
			ActualEndsAt:           actualEndsAt,
			PlannedDurationMinutes: plannedDurationMinutes,
			Status:                 row.Status,
			Notes:                  row.Notes,
			CreatedAt:              row.CreatedAt,
			UpdatedAt:              row.UpdatedAt,
		})
	}
	return items, nil
}
