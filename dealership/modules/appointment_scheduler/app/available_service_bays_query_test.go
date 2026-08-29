package app

import (
	"context"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type availableServiceBaysRepositoryStub struct {
	allowed       bool
	active        bool
	serviceBays   []domain.ServiceBay
	dealershipID  uuid.UUID
	startsAt      time.Time
	endsAt        time.Time
	listWasCalled bool
}

func (s *availableServiceBaysRepositoryStub) CanReadAvailableServiceBays(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return s.allowed, nil
}

func (s *availableServiceBaysRepositoryStub) IsActiveDealership(context.Context, uuid.UUID) (bool, error) {
	return s.active, nil
}

func (s *availableServiceBaysRepositoryStub) ListAvailableServiceBays(_ context.Context, dealershipID uuid.UUID, startsAt, endsAt time.Time) ([]domain.ServiceBay, error) {
	s.dealershipID = dealershipID
	s.startsAt = startsAt
	s.endsAt = endsAt
	s.listWasCalled = true
	return s.serviceBays, nil
}

func TestAvailableServiceBaysQueryListsBaysForHalfOpenInterval(t *testing.T) {
	dealershipID := uuid.New()
	serviceBay, err := domain.NewServiceBay(uuid.New(), dealershipID, "BAY-01", "Bay 01", true, time.Now())
	require.NoError(t, err)
	repository := &availableServiceBaysRepositoryStub{
		allowed:     true,
		active:      true,
		serviceBays: []domain.ServiceBay{serviceBay},
	}
	query := NewAvailableServiceBaysQuery(repository)
	startsAt := time.Date(2026, 8, 29, 8, 0, 0, 0, time.FixedZone("ICT", 7*60*60))
	endsAt := startsAt.Add(time.Hour)

	result, err := query.List(context.Background(), ListAvailableServiceBaysInput{
		ActorUserID:  uuid.New(),
		DealershipID: dealershipID,
		StartsAt:     startsAt,
		EndsAt:       endsAt,
	})

	require.NoError(t, err)
	require.Equal(t, []domain.ServiceBay{serviceBay}, result)
	require.True(t, repository.listWasCalled)
	require.Equal(t, dealershipID, repository.dealershipID)
	require.Equal(t, startsAt.UTC(), repository.startsAt)
	require.Equal(t, endsAt.UTC(), repository.endsAt)
}

func TestAvailableServiceBaysQueryValidatesTimeRangeAndAccess(t *testing.T) {
	dealershipID := uuid.New()
	startsAt := time.Date(2026, 8, 29, 8, 0, 0, 0, time.UTC)
	repository := &availableServiceBaysRepositoryStub{allowed: false, active: true}
	query := NewAvailableServiceBaysQuery(repository)

	_, err := query.List(context.Background(), ListAvailableServiceBaysInput{
		ActorUserID:  uuid.New(),
		DealershipID: dealershipID,
		StartsAt:     startsAt,
		EndsAt:       startsAt,
	})
	require.ErrorAs(t, err, new(common.Error))
	var structured common.Error
	require.ErrorAs(t, err, &structured)
	require.Equal(t, "invalid_time_range", structured.ErrorSlug)
	require.False(t, repository.listWasCalled)

	_, err = query.List(context.Background(), ListAvailableServiceBaysInput{
		ActorUserID:  uuid.New(),
		DealershipID: dealershipID,
		StartsAt:     startsAt,
		EndsAt:       startsAt.Add(time.Hour),
	})
	require.ErrorAs(t, err, &structured)
	require.Equal(t, "available_service_bays_access_forbidden", structured.ErrorSlug)
	require.False(t, repository.listWasCalled)
}
