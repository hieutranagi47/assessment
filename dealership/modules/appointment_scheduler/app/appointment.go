package app

import (
	"context"
	"errors"
	"fmt"
	"time"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
)

var (
	ErrAppointmentNotFound    = errors.New("appointment not found")
	ErrAppointmentUnavailable = errors.New("appointment resources are unavailable")
	ErrAppointmentForbidden   = errors.New("appointment access is forbidden")
)

type AppointmentRepository interface {
	GetEmployeeDealership(context.Context, uuid.UUID) (uuid.UUID, error)
	GetSchedulerUserID(context.Context, uuid.UUID) (uuid.UUID, error)
	ScheduleAppointment(context.Context, ScheduleAppointmentRecord) error
	TransitionAppointment(context.Context, AppointmentTransition) error
}

type AppointmentTransition struct {
	AppointmentID, DealershipID, ActorUserID uuid.UUID
	From, To                                 domain.AppointmentStatus
	OccurredAt                               time.Time
	ActualEndsAt                             *time.Time
	CancellationReason                       *string
	Note                                     *string
}

type ScheduleAppointmentInput struct {
	CustomerID             uuid.UUID
	VehicleID              uuid.UUID
	ServiceTypeID          uuid.UUID
	StartsAt               time.Time
	TechnicianID           uuid.UUID
	ServiceBayID           uuid.UUID
	PlannedDurationMinutes *int
	Notes                  *string
}

// ScheduleAppointmentRecord is an application/persistence write model. It is
// intentionally separate from HTTP and domain lifecycle models.
type ScheduleAppointmentRecord struct {
	AppointmentID, CustomerID, VehicleID, DealershipID, ServiceTypeID uuid.UUID
	TechnicianID, ServiceBayID, CreatedByUserID                       uuid.UUID
	ReferenceCode                                                     string
	StartsAt, EndsAt, CreatedAt, UpdatedAt                            time.Time
	PlannedDurationMinutes                                            int
	Notes                                                             *string
}

func (s *Service) ScheduleAppointment(ctx context.Context, actorID uuid.UUID, input ScheduleAppointmentInput) (ScheduleAppointmentRecord, error) {
	repository, ok := s.repository.(AppointmentRepository)
	if !ok {
		return ScheduleAppointmentRecord{}, errors.New("appointment repository is not configured")
	}
	if input.CustomerID == uuid.Nil || input.VehicleID == uuid.Nil || input.ServiceTypeID == uuid.Nil || input.TechnicianID == uuid.Nil || input.ServiceBayID == uuid.Nil {
		return ScheduleAppointmentRecord{}, common.NewInvalidInputError("validation_error", "appointment resource IDs are required")
	}
	if input.StartsAt.IsZero() || input.StartsAt.Location() != time.UTC {
		return ScheduleAppointmentRecord{}, common.NewInvalidInputError("validation_error", "starts_at must be a UTC timestamp")
	}
	if input.PlannedDurationMinutes != nil && *input.PlannedDurationMinutes <= 0 {
		return ScheduleAppointmentRecord{}, common.NewInvalidInputError("validation_error", "planned_duration_minutes must be positive")
	}
	dealershipID, err := repository.GetEmployeeDealership(ctx, actorID)
	if err != nil {
		return ScheduleAppointmentRecord{}, common.NewForbiddenError("forbidden", "appointment access is not permitted")
	}
	actorUserID, err := repository.GetSchedulerUserID(ctx, actorID)
	if err != nil {
		return ScheduleAppointmentRecord{}, common.NewForbiddenError("forbidden", "appointment access is not permitted")
	}
	now := s.now().UTC()
	record := ScheduleAppointmentRecord{
		AppointmentID: s.newID(), CustomerID: input.CustomerID, VehicleID: input.VehicleID,
		DealershipID: dealershipID, ServiceTypeID: input.ServiceTypeID,
		TechnicianID: input.TechnicianID, ServiceBayID: input.ServiceBayID,
		CreatedByUserID: actorUserID, ReferenceCode: fmt.Sprintf("APT-%s", s.newID().String()[:8]),
		StartsAt: input.StartsAt.UTC(), CreatedAt: now, UpdatedAt: now,
		Notes: input.Notes,
	}
	if input.PlannedDurationMinutes != nil {
		record.PlannedDurationMinutes = *input.PlannedDurationMinutes
	}
	if err := repository.ScheduleAppointment(ctx, record); err != nil {
		if errors.Is(err, ErrAppointmentUnavailable) {
			return ScheduleAppointmentRecord{}, common.NewConflictError("availability_conflict", "the selected technician or service bay is unavailable")
		}
		return ScheduleAppointmentRecord{}, err
	}
	return record, nil
}

func (s *Service) ChangeAppointmentStatus(ctx context.Context, actorID, appointmentID uuid.UUID, from, to domain.AppointmentStatus, actualEndsAt *time.Time, cancellationReason, note *string) error {
	if actorID == uuid.Nil || appointmentID == uuid.Nil {
		return common.NewInvalidInputError("validation_error", "appointment and actor IDs are required")
	}
	if from != "" && !validAppointmentTransition(from, to) {
		return common.NewConflictError("invalid_state_transition", "the appointment cannot transition from %s to %s", from, to)
	}
	if to == domain.AppointmentCancelled && (cancellationReason == nil || *cancellationReason == "") {
		return common.NewInvalidInputError("validation_error", "cancellation reason is required")
	}
	repository, ok := s.repository.(AppointmentRepository)
	if !ok {
		return errors.New("appointment repository is not configured")
	}
	dealershipID, err := repository.GetEmployeeDealership(ctx, actorID)
	if err != nil {
		return common.NewForbiddenError("forbidden", "appointment access is not permitted")
	}
	actorUserID, err := repository.GetSchedulerUserID(ctx, actorID)
	if err != nil {
		return common.NewForbiddenError("forbidden", "appointment access is not permitted")
	}
	if actualEndsAt != nil {
		value := actualEndsAt.UTC()
		actualEndsAt = &value
	}
	return repository.TransitionAppointment(ctx, AppointmentTransition{
		AppointmentID: appointmentID, DealershipID: dealershipID, ActorUserID: actorUserID,
		From: from, To: to, OccurredAt: s.now().UTC(), ActualEndsAt: actualEndsAt,
		CancellationReason: cancellationReason, Note: note,
	})
}

func validAppointmentTransition(from, to domain.AppointmentStatus) bool {
	return (from == domain.AppointmentRequested && to == domain.AppointmentCheckedIn) ||
		(from == domain.AppointmentCheckedIn && to == domain.AppointmentInProgress) ||
		(from == domain.AppointmentInProgress && to == domain.AppointmentCompleted) ||
		((from == domain.AppointmentRequested || from == domain.AppointmentCheckedIn || from == domain.AppointmentInProgress) && to == domain.AppointmentCancelled)
}
