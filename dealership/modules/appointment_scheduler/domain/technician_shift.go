package domain

import (
	"errors"
	"time"

	"github.com/google/uuid"
)

var (
	ErrTechnicianShiftIDRequired = errors.New("technician shift ID is required")
	ErrInvalidShiftWeekday       = errors.New("day of week must be between 1 and 7")
	ErrInvalidShiftClock         = errors.New("shift times must be local HH:MM values")
	ErrInvalidShiftHours         = errors.New("starts at must be earlier than ends at")
)

// TechnicianShift is one weekly local wall-clock availability interval.
type TechnicianShift struct {
	id, technicianID     uuid.UUID
	dayOfWeek            int
	startsAt, endsAt     time.Duration
	createdAt, updatedAt time.Time
}

func NewTechnicianShift(id, technicianID uuid.UUID, dayOfWeek int, startsAt, endsAt time.Duration, now time.Time) (TechnicianShift, error) {
	if id == uuid.Nil {
		return TechnicianShift{}, ErrTechnicianShiftIDRequired
	}
	if technicianID == uuid.Nil {
		return TechnicianShift{}, ErrTechnicianIDRequired
	}
	if dayOfWeek < 1 || dayOfWeek > 7 {
		return TechnicianShift{}, ErrInvalidShiftWeekday
	}
	if startsAt < 0 || startsAt >= 24*time.Hour || endsAt < 0 || endsAt >= 24*time.Hour {
		return TechnicianShift{}, ErrInvalidShiftClock
	}
	if startsAt >= endsAt {
		return TechnicianShift{}, ErrInvalidShiftHours
	}
	now = now.UTC()
	return TechnicianShift{id: id, technicianID: technicianID, dayOfWeek: dayOfWeek, startsAt: startsAt, endsAt: endsAt, createdAt: now, updatedAt: now}, nil
}

func RehydrateTechnicianShift(id, technicianID uuid.UUID, dayOfWeek int, startsAt, endsAt time.Duration, createdAt, updatedAt time.Time) (TechnicianShift, error) {
	shift, err := NewTechnicianShift(id, technicianID, dayOfWeek, startsAt, endsAt, createdAt)
	if err != nil {
		return TechnicianShift{}, err
	}
	shift.updatedAt = updatedAt.UTC()
	return shift, nil
}

func (s TechnicianShift) Update(dayOfWeek int, startsAt, endsAt time.Duration, now time.Time) (TechnicianShift, error) {
	updated, err := NewTechnicianShift(s.id, s.technicianID, dayOfWeek, startsAt, endsAt, s.createdAt)
	if err != nil {
		return TechnicianShift{}, err
	}
	updated.updatedAt = now.UTC()
	return updated, nil
}

func (s TechnicianShift) ID() uuid.UUID           { return s.id }
func (s TechnicianShift) TechnicianID() uuid.UUID { return s.technicianID }
func (s TechnicianShift) DayOfWeek() int          { return s.dayOfWeek }
func (s TechnicianShift) StartsAt() time.Duration { return s.startsAt }
func (s TechnicianShift) EndsAt() time.Duration   { return s.endsAt }
func (s TechnicianShift) CreatedAt() time.Time    { return s.createdAt }
func (s TechnicianShift) UpdatedAt() time.Time    { return s.updatedAt }
