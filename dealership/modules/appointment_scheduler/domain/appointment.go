package domain

import (
	"errors"
	"time"

	"github.com/google/uuid"
)

type AppointmentStatus string

const (
	AppointmentRequested  AppointmentStatus = "requested"
	AppointmentCheckedIn  AppointmentStatus = "checked_in"
	AppointmentInProgress AppointmentStatus = "in_progress"
	AppointmentCompleted  AppointmentStatus = "completed"
	AppointmentCancelled  AppointmentStatus = "cancelled"
)

var (
	ErrAppointmentIDRequired    = errors.New("appointment ID is required")
	ErrAppointmentInterval      = errors.New("appointment end must be after start")
	ErrInvalidStatusTransition  = errors.New("invalid appointment status transition")
	ErrCompletionOutsidePlanned = errors.New("completion time must be within the checked-in planned interval")
	ErrCancellationReason       = errors.New("cancellation reason is required")
)

// Appointment owns lifecycle rules. Scheduling eligibility and persistence are
// deliberately handled by the application service and repository transaction.
type Appointment struct {
	id                 uuid.UUID
	status             AppointmentStatus
	startsAt, endsAt   time.Time
	checkedInAt        *time.Time
	inProgressAt       *time.Time
	completedAt        *time.Time
	actualEndsAt       *time.Time
	cancelledAt        *time.Time
	cancellationReason *string
}

func NewAppointment(id uuid.UUID, startsAt, endsAt time.Time) (Appointment, error) {
	if id == uuid.Nil {
		return Appointment{}, ErrAppointmentIDRequired
	}
	startsAt = startsAt.UTC()
	endsAt = endsAt.UTC()
	if !endsAt.After(startsAt) {
		return Appointment{}, ErrAppointmentInterval
	}
	return Appointment{id: id, status: AppointmentRequested, startsAt: startsAt, endsAt: endsAt}, nil
}

func (a Appointment) CheckIn(now time.Time) (Appointment, error) {
	if a.status != AppointmentRequested {
		return Appointment{}, ErrInvalidStatusTransition
	}
	now = now.UTC()
	a.status = AppointmentCheckedIn
	a.checkedInAt = &now
	return a, nil
}

func (a Appointment) Start(now time.Time) (Appointment, error) {
	if a.status != AppointmentCheckedIn {
		return Appointment{}, ErrInvalidStatusTransition
	}
	now = now.UTC()
	a.status = AppointmentInProgress
	a.inProgressAt = &now
	return a, nil
}

func (a Appointment) Complete(actualEndsAt time.Time) (Appointment, error) {
	if a.status != AppointmentInProgress || a.checkedInAt == nil {
		return Appointment{}, ErrInvalidStatusTransition
	}
	actualEndsAt = actualEndsAt.UTC()
	if actualEndsAt.Before(*a.checkedInAt) || actualEndsAt.After(a.endsAt) {
		return Appointment{}, ErrCompletionOutsidePlanned
	}
	a.status = AppointmentCompleted
	a.completedAt = &actualEndsAt
	a.actualEndsAt = &actualEndsAt
	return a, nil
}

func (a Appointment) Cancel(reason string, now time.Time) (Appointment, error) {
	if a.status != AppointmentRequested && a.status != AppointmentCheckedIn && a.status != AppointmentInProgress {
		return Appointment{}, ErrInvalidStatusTransition
	}
	if reason == "" {
		return Appointment{}, ErrCancellationReason
	}
	now = now.UTC()
	a.status = AppointmentCancelled
	a.cancelledAt = &now
	a.cancellationReason = &reason
	return a, nil
}

func (a Appointment) ID() uuid.UUID               { return a.id }
func (a Appointment) Status() AppointmentStatus   { return a.status }
func (a Appointment) StartsAt() time.Time         { return a.startsAt }
func (a Appointment) EndsAt() time.Time           { return a.endsAt }
func (a Appointment) CheckedInAt() *time.Time     { return copyTime(a.checkedInAt) }
func (a Appointment) ActualEndsAt() *time.Time    { return copyTime(a.actualEndsAt) }
func (a Appointment) CancellationReason() *string { return copyString(a.cancellationReason) }

func copyTime(value *time.Time) *time.Time {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}
