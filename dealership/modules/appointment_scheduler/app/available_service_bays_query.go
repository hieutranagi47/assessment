package app

import (
	"context"
	"time"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
)

// AvailableServiceBayRepository is the read port for selecting bays that are
// unreserved for a requested half-open interval.
type AvailableServiceBayRepository interface {
	CanReadAvailableServiceBays(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	IsActiveDealership(context.Context, uuid.UUID) (bool, error)
	ListAvailableServiceBays(context.Context, uuid.UUID, time.Time, time.Time) ([]domain.ServiceBay, error)
}

type ListAvailableServiceBaysInput struct {
	ActorUserID  uuid.UUID
	DealershipID uuid.UUID
	StartsAt     time.Time
	EndsAt       time.Time
}

// AvailableServiceBaysQuery returns active bays without an active appointment
// overlapping the requested [starts_at, ends_at) interval.
type AvailableServiceBaysQuery struct {
	repository AvailableServiceBayRepository
}

func NewAvailableServiceBaysQuery(repository AvailableServiceBayRepository) *AvailableServiceBaysQuery {
	if repository == nil {
		panic("available service bays query repository is required")
	}
	return &AvailableServiceBaysQuery{repository: repository}
}

func (q *AvailableServiceBaysQuery) List(ctx context.Context, input ListAvailableServiceBaysInput) ([]domain.ServiceBay, error) {
	if input.ActorUserID == uuid.Nil {
		return nil, common.NewUnauthorizedError("authentication_required", "authentication is required")
	}
	if input.DealershipID == uuid.Nil {
		return nil, common.NewInvalidInputError("invalid_dealership_id", "dealership ID is required")
	}
	if input.StartsAt.IsZero() {
		return nil, common.NewInvalidInputError("invalid_starts_at", "starts_at is required")
	}
	if input.EndsAt.IsZero() {
		return nil, common.NewInvalidInputError("invalid_ends_at", "ends_at is required")
	}
	if !input.EndsAt.After(input.StartsAt) {
		return nil, common.NewInvalidInputError("invalid_time_range", "ends_at must be after starts_at")
	}

	allowed, err := q.repository.CanReadAvailableServiceBays(ctx, input.ActorUserID, input.DealershipID)
	if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, common.NewForbiddenError("available_service_bays_access_forbidden", "you are not allowed to view available service bays for this dealership")
	}

	isActive, err := q.repository.IsActiveDealership(ctx, input.DealershipID)
	if err != nil {
		return nil, err
	}
	if !isActive {
		return nil, common.NewNotFoundError("dealership_not_found", "dealership was not found")
	}

	return q.repository.ListAvailableServiceBays(ctx, input.DealershipID, input.StartsAt.UTC(), input.EndsAt.UTC())
}
