package app

import (
	"context"
	"errors"
	"time"

	"assessment/modules/common"

	"github.com/google/uuid"
)

var ErrDealershipAppointmentsDealershipNotFound = errors.New("dealership appointments dealership not found")

// DealershipAppointmentsRepository is the read port for a dealership's daily
// appointment list. Its values are read models, not HTTP response models.
type DealershipAppointmentsRepository interface {
	CanReadDealershipAppointments(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	GetActiveDealershipForAppointments(context.Context, uuid.UUID) (DealershipAppointmentsDealership, error)
	ListDealershipAppointments(context.Context, uuid.UUID, time.Time, time.Time) ([]DealershipAppointment, error)
}

type DealershipAppointmentsDealership struct {
	ID       uuid.UUID
	Timezone string
}

type DealershipAppointment struct {
	AppointmentID          uuid.UUID
	ReferenceCode          string
	CustomerID             uuid.UUID
	VehicleID              uuid.UUID
	DealershipID           uuid.UUID
	ServiceTypeID          uuid.UUID
	TechnicianID           uuid.UUID
	ServiceBayID           uuid.UUID
	StartsAt               time.Time
	EndsAt                 time.Time
	ActualEndsAt           *time.Time
	PlannedDurationMinutes int
	Status                 string
	Notes                  *string
	CreatedAt              time.Time
	UpdatedAt              time.Time
}

type ListDealershipAppointmentsInput struct {
	ActorUserID  uuid.UUID
	DealershipID uuid.UUID
	Date         string
}

type DealershipAppointmentsResult struct {
	Date         time.Time
	Timezone     string
	Appointments []DealershipAppointment
}

type DealershipAppointmentsQuery struct {
	repository DealershipAppointmentsRepository
}

func NewDealershipAppointmentsQuery(repository DealershipAppointmentsRepository) *DealershipAppointmentsQuery {
	if repository == nil {
		panic("dealership appointments query repository is required")
	}
	return &DealershipAppointmentsQuery{repository: repository}
}

func (q *DealershipAppointmentsQuery) List(ctx context.Context, input ListDealershipAppointmentsInput) (DealershipAppointmentsResult, error) {
	if input.ActorUserID == uuid.Nil {
		return DealershipAppointmentsResult{}, common.NewUnauthorizedError("authentication_required", "authentication is required")
	}
	if input.DealershipID == uuid.Nil {
		return DealershipAppointmentsResult{}, common.NewInvalidInputError("invalid_dealership_id", "dealership ID is required")
	}
	date, err := time.Parse("2006-01-02", input.Date)
	if err != nil || date.Format("2006-01-02") != input.Date {
		return DealershipAppointmentsResult{}, common.NewInvalidInputError("invalid_date", "date must use YYYY-MM-DD")
	}

	allowed, err := q.repository.CanReadDealershipAppointments(ctx, input.ActorUserID, input.DealershipID)
	if err != nil {
		return DealershipAppointmentsResult{}, err
	}
	if !allowed {
		return DealershipAppointmentsResult{}, common.NewForbiddenError("dealership_appointments_access_forbidden", "you are not allowed to view appointments for this dealership")
	}

	dealership, err := q.repository.GetActiveDealershipForAppointments(ctx, input.DealershipID)
	if errors.Is(err, ErrDealershipAppointmentsDealershipNotFound) {
		return DealershipAppointmentsResult{}, common.NewNotFoundError("dealership_not_found", "dealership was not found")
	}
	if err != nil {
		return DealershipAppointmentsResult{}, err
	}
	location, err := time.LoadLocation(dealership.Timezone)
	if err != nil {
		return DealershipAppointmentsResult{}, err
	}
	localStart := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, location)
	localEnd := localStart.AddDate(0, 0, 1)
	appointments, err := q.repository.ListDealershipAppointments(ctx, dealership.ID, localStart.UTC(), localEnd.UTC())
	if err != nil {
		return DealershipAppointmentsResult{}, err
	}
	return DealershipAppointmentsResult{Date: date, Timezone: dealership.Timezone, Appointments: appointments}, nil
}
