package domain

import (
	"errors"
	"time"

	"github.com/google/uuid"
)

var (
	ErrOperationTimeIDRequired = errors.New("operation time ID is required")
	ErrInvalidOperationWeekday = errors.New("day of week must be between 1 and 7")
	ErrInvalidOperationClock   = errors.New("operation times must be local HH:MM values")
	ErrInvalidOperationHours   = errors.New("opens at must be earlier than closes at")
)

// DealershipOperationTime is one local wall-clock opening interval.
type DealershipOperationTime struct {
	id, dealershipID     uuid.UUID
	dayOfWeek            int
	opensAt, closesAt    time.Duration
	createdAt, updatedAt time.Time
}

func NewDealershipOperationTime(id, dealershipID uuid.UUID, dayOfWeek int, opensAt, closesAt time.Duration, now time.Time) (DealershipOperationTime, error) {
	if id == uuid.Nil {
		return DealershipOperationTime{}, ErrOperationTimeIDRequired
	}
	if dealershipID == uuid.Nil {
		return DealershipOperationTime{}, ErrDealershipIDRequired
	}
	if dayOfWeek < 1 || dayOfWeek > 7 {
		return DealershipOperationTime{}, ErrInvalidOperationWeekday
	}
	if opensAt < 0 || opensAt >= 24*time.Hour || closesAt < 0 || closesAt >= 24*time.Hour {
		return DealershipOperationTime{}, ErrInvalidOperationClock
	}
	if opensAt >= closesAt {
		return DealershipOperationTime{}, ErrInvalidOperationHours
	}
	now = now.UTC()
	return DealershipOperationTime{id: id, dealershipID: dealershipID, dayOfWeek: dayOfWeek, opensAt: opensAt, closesAt: closesAt, createdAt: now, updatedAt: now}, nil
}

func RehydrateDealershipOperationTime(id, dealershipID uuid.UUID, dayOfWeek int, opensAt, closesAt time.Duration, createdAt, updatedAt time.Time) (DealershipOperationTime, error) {
	operationTime, err := NewDealershipOperationTime(id, dealershipID, dayOfWeek, opensAt, closesAt, createdAt)
	if err != nil {
		return DealershipOperationTime{}, err
	}
	operationTime.updatedAt = updatedAt.UTC()
	return operationTime, nil
}

func (o DealershipOperationTime) Update(dayOfWeek int, opensAt, closesAt time.Duration, now time.Time) (DealershipOperationTime, error) {
	updated, err := NewDealershipOperationTime(o.id, o.dealershipID, dayOfWeek, opensAt, closesAt, o.createdAt)
	if err != nil {
		return DealershipOperationTime{}, err
	}
	updated.updatedAt = now.UTC()
	return updated, nil
}

func (o DealershipOperationTime) ID() uuid.UUID           { return o.id }
func (o DealershipOperationTime) DealershipID() uuid.UUID { return o.dealershipID }
func (o DealershipOperationTime) DayOfWeek() int          { return o.dayOfWeek }
func (o DealershipOperationTime) OpensAt() time.Duration  { return o.opensAt }
func (o DealershipOperationTime) ClosesAt() time.Duration { return o.closesAt }
func (o DealershipOperationTime) CreatedAt() time.Time    { return o.createdAt }
func (o DealershipOperationTime) UpdatedAt() time.Time    { return o.updatedAt }
