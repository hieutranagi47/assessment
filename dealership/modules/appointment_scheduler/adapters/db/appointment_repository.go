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
		var timezone string
		err := tx.QueryRow(ctx, `SELECT timezone FROM appointment_scheduler.dealerships WHERE dealership_id = $1 AND is_active AND deleted_at IS NULL`, record.DealershipID).Scan(&timezone)
		if errors.Is(err, pgx.ErrNoRows) {
			return common.NewNotFoundError("not_found", "dealership not found")
		}
		if err != nil {
			return err
		}

		var minDuration, maxDuration int
		err = tx.QueryRow(ctx, `SELECT min_duration_minutes, max_duration_minutes FROM appointment_scheduler.service_types WHERE service_type_id = $1 AND dealership_id = $2 AND is_active AND deleted_at IS NULL`, record.ServiceTypeID, record.DealershipID).Scan(&minDuration, &maxDuration)
		if errors.Is(err, pgx.ErrNoRows) {
			return common.NewNotFoundError("not_found", "service type not found")
		}
		if err != nil {
			return err
		}
		if record.PlannedDurationMinutes == 0 {
			record.PlannedDurationMinutes = maxDuration
		}
		if record.PlannedDurationMinutes < minDuration || record.PlannedDurationMinutes > maxDuration {
			return common.NewInvalidInputError("validation_error", "planned duration must be between %d and %d minutes", minDuration, maxDuration)
		}
		record.EndsAt = record.StartsAt.Add(time.Duration(record.PlannedDurationMinutes) * time.Minute)

		var valid bool
		err = tx.QueryRow(ctx, `SELECT EXISTS (
  SELECT 1 FROM appointment_scheduler.customer_dealerships cd
  JOIN appointment_scheduler.vehicles v ON v.customer_id = cd.customer_id AND v.vehicle_id = $2 AND v.deleted_at IS NULL
  WHERE cd.customer_id = $1 AND cd.dealership_id = $3
)`, record.CustomerID, record.VehicleID, record.DealershipID).Scan(&valid)
		if err != nil {
			return err
		}
		if !valid {
			return common.Error{HttpErrorCode: 422, PublicError: "vehicle does not belong to the customer in this dealership", ErrorSlug: "invalid_customer_vehicle"}
		}

		// A single local-day interval and one operating-hours row are required;
		// unsupported cross-boundary bookings are deliberately rejected.
		err = tx.QueryRow(ctx, `SELECT EXISTS (
  SELECT 1 FROM appointment_scheduler.dealership_operation_time ot
  WHERE ot.dealership_id = $1
    AND ot.day_of_week = EXTRACT(ISODOW FROM $2 AT TIME ZONE $3)::smallint
    AND ($2 AT TIME ZONE $3)::date = ($4 AT TIME ZONE $3)::date
    AND ($2 AT TIME ZONE $3)::time >= ot.opens_at
    AND ($4 AT TIME ZONE $3)::time <= ot.closes_at
)`, record.DealershipID, record.StartsAt, timezone, record.EndsAt).Scan(&valid)
		if err != nil {
			return err
		}
		if !valid {
			return common.Error{HttpErrorCode: 422, PublicError: "appointment is outside dealership operating hours", ErrorSlug: "operating_hours_violation"}
		}

		err = tx.QueryRow(ctx, `SELECT EXISTS (
  SELECT 1 FROM appointment_scheduler.technicians t
  JOIN appointment_scheduler.users u ON u.user_id = t.user_id
  WHERE t.technician_id = $1 AND u.dealership_id = $2 AND t.is_active AND t.deleted_at IS NULL AND u.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM appointment_scheduler.service_type_required_skills required
      WHERE required.service_type_id = $3 AND NOT EXISTS (
        SELECT 1 FROM appointment_scheduler.technician_skills skill
        WHERE skill.technician_id = t.technician_id AND skill.skill_id = required.skill_id
      )
    )
)`, record.TechnicianID, record.DealershipID, record.ServiceTypeID).Scan(&valid)
		if err != nil {
			return err
		}
		if !valid {
			return common.Error{HttpErrorCode: 422, PublicError: "technician is inactive or lacks required skills", ErrorSlug: "incompatible_technician"}
		}

		err = tx.QueryRow(ctx, `SELECT EXISTS (
  SELECT 1 FROM appointment_scheduler.service_bays b
  WHERE b.service_bay_id = $1 AND b.dealership_id = $2 AND b.is_active AND b.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM appointment_scheduler.service_type_required_bay_capabilities required
      WHERE required.service_type_id = $3 AND NOT EXISTS (
        SELECT 1 FROM appointment_scheduler.service_bay_capabilities capability
        WHERE capability.service_bay_id = b.service_bay_id AND capability.bay_capability_id = required.bay_capability_id
      )
    )
)`, record.ServiceBayID, record.DealershipID, record.ServiceTypeID).Scan(&valid)
		if err != nil {
			return err
		}
		if !valid {
			return common.Error{HttpErrorCode: 422, PublicError: "service bay is inactive or incompatible", ErrorSlug: "incompatible_service_bay"}
		}

		err = tx.QueryRow(ctx, `SELECT EXISTS (
  SELECT 1 FROM appointment_scheduler.technician_shifts s
  WHERE s.technician_id = $1 AND s.deleted_at IS NULL
    AND s.day_of_week = EXTRACT(ISODOW FROM $2 AT TIME ZONE $3)::smallint
    AND ($2 AT TIME ZONE $3)::date = ($4 AT TIME ZONE $3)::date
    AND ($2 AT TIME ZONE $3)::time >= s.starts_at AND ($4 AT TIME ZONE $3)::time <= s.ends_at
) AND NOT EXISTS (
  SELECT 1 FROM appointment_scheduler.technician_time_off t
  WHERE t.technician_id = $1 AND t.deleted_at IS NULL AND t.starts_at < $4 AND t.ends_at > $2
)`, record.TechnicianID, record.StartsAt, timezone, record.EndsAt).Scan(&valid)
		if err != nil {
			return err
		}
		if !valid {
			return common.Error{HttpErrorCode: 422, PublicError: "technician shift or time off prevents this appointment", ErrorSlug: "technician_schedule_violation"}
		}

		_, err = tx.Exec(ctx, `INSERT INTO appointment_scheduler.appointments (
  appointment_id, reference_code, customer_id, vehicle_id, dealership_id, service_type_id, technician_id, service_bay_id,
  starts_at, ends_at, planned_duration_minutes, status, notes, created_by_user_id, created_at, updated_at
) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'requested',$12,$13,$14,$15)`,
			record.AppointmentID, record.ReferenceCode, record.CustomerID, record.VehicleID, record.DealershipID, record.ServiceTypeID, record.TechnicianID, record.ServiceBayID, record.StartsAt, record.EndsAt, record.PlannedDurationMinutes, record.Notes, record.CreatedByUserID, record.CreatedAt, record.UpdatedAt)
		if err != nil {
			return appointmentWriteError(err)
		}
		queries := r.queries.WithTx(tx)
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
		var status string
		var startsAt, endsAt time.Time
		var notes *string
		err := tx.QueryRow(ctx, `SELECT status, starts_at, ends_at, notes
FROM appointment_scheduler.appointments
WHERE appointment_id = $1 AND dealership_id = $2 AND deleted_at IS NULL
FOR UPDATE`, transition.AppointmentID, transition.DealershipID).Scan(&status, &startsAt, &endsAt, &notes)
		if errors.Is(err, pgx.ErrNoRows) {
			return common.NewNotFoundError("not_found", "appointment not found")
		}
		if err != nil {
			return err
		}
		if transition.From != "" && status != string(transition.From) {
			return common.NewConflictError("invalid_state_transition", "the appointment is no longer in the expected state")
		}
		if transition.To == "cancelled" && status != "requested" && status != "checked_in" && status != "in_progress" {
			return common.NewConflictError("invalid_state_transition", "the appointment cannot be cancelled from its current state")
		}

		before, err := json.Marshal(map[string]any{"status": status, "notes": notes})
		if err != nil {
			return fmt.Errorf("marshal appointment audit before state: %w", err)
		}
		updatedNotes := notes
		if transition.Note != nil {
			updatedNotes = transition.Note
		}
		actualEndsAt := transition.ActualEndsAt
		if transition.To == "completed" {
			if actualEndsAt == nil {
				actualEndsAt = &transition.OccurredAt
			}
			var checkedInAt *time.Time
			err = tx.QueryRow(ctx, `SELECT checked_in_at FROM appointment_scheduler.appointments WHERE appointment_id = $1`, transition.AppointmentID).Scan(&checkedInAt)
			if err != nil {
				return err
			}
			if checkedInAt == nil || actualEndsAt.Before(*checkedInAt) || actualEndsAt.After(endsAt) {
				return common.NewInvalidInputError("validation_error", "actual_ends_at must be between check-in and the planned end")
			}
		}

		switch transition.To {
		case "checked_in":
			_, err = tx.Exec(ctx, `UPDATE appointment_scheduler.appointments SET status = $1, checked_in_at = $2, notes = $3, updated_at = $2 WHERE appointment_id = $4`, transition.To, transition.OccurredAt, updatedNotes, transition.AppointmentID)
		case "in_progress":
			_, err = tx.Exec(ctx, `UPDATE appointment_scheduler.appointments SET status = $1, in_progress_at = $2, started_at = $2, notes = $3, updated_at = $2 WHERE appointment_id = $4`, transition.To, transition.OccurredAt, updatedNotes, transition.AppointmentID)
		case "completed":
			_, err = tx.Exec(ctx, `UPDATE appointment_scheduler.appointments SET status = $1, completed_at = $2, actual_ends_at = $3, notes = $4, updated_at = $2 WHERE appointment_id = $5`, transition.To, transition.OccurredAt, actualEndsAt, updatedNotes, transition.AppointmentID)
		case "cancelled":
			_, err = tx.Exec(ctx, `UPDATE appointment_scheduler.appointments SET status = $1, cancelled_at = $2, cancelled_by_user_id = $3, cancellation_reason = $4, notes = $5, updated_at = $2 WHERE appointment_id = $6`, transition.To, transition.OccurredAt, transition.ActorUserID, transition.CancellationReason, updatedNotes, transition.AppointmentID)
		default:
			return common.NewConflictError("invalid_state_transition", "unsupported appointment state")
		}
		if err != nil {
			return err
		}
		if transition.To == "completed" || transition.To == "cancelled" {
			_, err = r.queries.WithTx(tx).ReleaseAppointmentResourceReservations(ctx, dbmodels.ReleaseAppointmentResourceReservationsParams{ReleasedAt: pgTimestamptz(transition.OccurredAt), Status: string(transition.To), AppointmentID: toPGUUID(transition.AppointmentID)})
			if err != nil {
				return err
			}
		}
		after, err := json.Marshal(map[string]any{"status": transition.To, "notes": updatedNotes, "actual_ends_at": actualEndsAt, "cancellation_reason": transition.CancellationReason})
		if err != nil {
			return fmt.Errorf("marshal appointment audit after state: %w", err)
		}
		return r.queries.WithTx(tx).CreateAppointmentAuditEvents(ctx, dbmodels.CreateAppointmentAuditEventsParams{AppointmentAuditEventID: toPGUUID(uuid.New()), AppointmentID: toPGUUID(transition.AppointmentID), ActorUserID: toPGUUID(transition.ActorUserID), EventType: "status_changed", BeforeData: before, AfterData: after, OccurredAt: transition.OccurredAt})
	})
}

func pgTimestamptz(value time.Time) pgtype.Timestamptz {
	return pgtype.Timestamptz{Time: value.UTC(), Valid: true}
}
