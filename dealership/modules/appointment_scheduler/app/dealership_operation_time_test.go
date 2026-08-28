package app

import (
	"context"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/domain"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type operationTimeRepositoryStub struct {
	admin, active bool
	items         map[uuid.UUID]domain.DealershipOperationTime
	createErr     error
}

func (r *operationTimeRepositoryStub) Create(context.Context, domain.Dealership) error { return nil }
func (r *operationTimeRepositoryStub) IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return r.admin, nil
}
func (r *operationTimeRepositoryStub) IsActiveDealership(context.Context, uuid.UUID) (bool, error) {
	return r.active, nil
}
func (r *operationTimeRepositoryStub) CreateDealershipOperationTime(_ context.Context, item domain.DealershipOperationTime) error {
	if r.createErr != nil {
		return r.createErr
	}
	for _, existing := range r.items {
		if existing.DayOfWeek() == item.DayOfWeek() && existing.OpensAt() < item.ClosesAt() && item.OpensAt() < existing.ClosesAt() {
			return ErrDealershipOperationTimeOverlaps
		}
	}
	r.items[item.ID()] = item
	return nil
}
func (r *operationTimeRepositoryStub) GetDealershipOperationTime(_ context.Context, dealershipID, itemID uuid.UUID) (domain.DealershipOperationTime, error) {
	item, ok := r.items[itemID]
	if !ok || item.DealershipID() != dealershipID {
		return domain.DealershipOperationTime{}, ErrDealershipOperationTimeNotFound
	}
	return item, nil
}
func (r *operationTimeRepositoryStub) ListDealershipOperationTimes(_ context.Context, dealershipID uuid.UUID) ([]domain.DealershipOperationTime, error) {
	items := make([]domain.DealershipOperationTime, 0, len(r.items))
	for _, item := range r.items {
		if item.DealershipID() == dealershipID {
			items = append(items, item)
		}
	}
	return items, nil
}
func (r *operationTimeRepositoryStub) UpdateDealershipOperationTime(ctx context.Context, item domain.DealershipOperationTime) error {
	delete(r.items, item.ID())
	return r.CreateDealershipOperationTime(ctx, item)
}
func (r *operationTimeRepositoryStub) DeleteDealershipOperationTime(_ context.Context, dealershipID, itemID uuid.UUID) error {
	item, err := r.GetDealershipOperationTime(context.Background(), dealershipID, itemID)
	if err != nil {
		return err
	}
	delete(r.items, item.ID())
	return nil
}

func TestDealershipOperationTimeAuthorizationIntervalsAndValidation(t *testing.T) {
	actor, dealershipID := uuid.New(), uuid.New()
	repository := &operationTimeRepositoryStub{admin: true, active: true, items: map[uuid.UUID]domain.DealershipOperationTime{}}
	service := NewService(repository, userInfoStub{})
	service.newID = uuid.New

	first, err := service.CreateDealershipOperationTime(context.Background(), actor, dealershipID, CreateDealershipOperationTimeInput{DayOfWeek: 1, OpensAt: 8 * time.Hour, ClosesAt: 12 * time.Hour})
	require.NoError(t, err)
	_, err = service.CreateDealershipOperationTime(context.Background(), actor, dealershipID, CreateDealershipOperationTimeInput{DayOfWeek: 1, OpensAt: 12 * time.Hour, ClosesAt: 17 * time.Hour})
	require.NoError(t, err, "adjacent intervals are valid")
	_, err = service.CreateDealershipOperationTime(context.Background(), actor, dealershipID, CreateDealershipOperationTimeInput{DayOfWeek: 1, OpensAt: 11 * time.Hour, ClosesAt: 13 * time.Hour})
	require.ErrorContains(t, err, "operation_time_overlaps")
	_, err = service.CreateDealershipOperationTime(context.Background(), actor, dealershipID, CreateDealershipOperationTimeInput{DayOfWeek: 8, OpensAt: 8 * time.Hour, ClosesAt: 9 * time.Hour})
	require.ErrorContains(t, err, "invalid_operation_time")
	_, err = service.UpdateDealershipOperationTime(context.Background(), actor, dealershipID, first.ID(), UpdateDealershipOperationTimeInput{OpensAt: durationPtr(12 * time.Hour)})
	require.ErrorContains(t, err, "invalid_operation_time")

	denied := NewService(&operationTimeRepositoryStub{items: map[uuid.UUID]domain.DealershipOperationTime{}}, userInfoStub{})
	_, err = denied.CreateDealershipOperationTime(context.Background(), actor, dealershipID, CreateDealershipOperationTimeInput{DayOfWeek: 1, OpensAt: 8 * time.Hour, ClosesAt: 9 * time.Hour})
	require.ErrorContains(t, err, "operation_time_access_forbidden")
}

func durationPtr(value time.Duration) *time.Duration { return &value }
