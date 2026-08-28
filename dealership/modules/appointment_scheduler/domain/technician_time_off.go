package domain

import (
	"errors"
	"time"

	"github.com/google/uuid"
)

var (
	ErrTechnicianTimeOffIDRequired = errors.New("technician time off ID is required")
	ErrInvalidTimeOffInterval      = errors.New("ends at must be after starts at")
)

// TechnicianTimeOff is an explicitly unavailable UTC interval for a technician.
type TechnicianTimeOff struct {
	id, technicianID, createdByUserID uuid.UUID
	startsAt, endsAt                  time.Time
	reason                            *string
	createdAt, updatedAt              time.Time
}

func NewTechnicianTimeOff(id, technicianID, createdByUserID uuid.UUID, startsAt, endsAt time.Time, reason *string, now time.Time) (TechnicianTimeOff, error) {
	if id == uuid.Nil {
		return TechnicianTimeOff{}, ErrTechnicianTimeOffIDRequired
	}
	if technicianID == uuid.Nil {
		return TechnicianTimeOff{}, ErrTechnicianIDRequired
	}
	if createdByUserID == uuid.Nil {
		return TechnicianTimeOff{}, errors.New("created by user ID is required")
	}
	startsAt = startsAt.UTC()
	endsAt = endsAt.UTC()
	if !endsAt.After(startsAt) {
		return TechnicianTimeOff{}, ErrInvalidTimeOffInterval
	}
	now = now.UTC()
	return TechnicianTimeOff{id: id, technicianID: technicianID, createdByUserID: createdByUserID, startsAt: startsAt, endsAt: endsAt, reason: reason, createdAt: now, updatedAt: now}, nil
}

func RehydrateTechnicianTimeOff(id, technicianID, createdByUserID uuid.UUID, startsAt, endsAt time.Time, reason *string, createdAt, updatedAt time.Time) (TechnicianTimeOff, error) {
	item, err := NewTechnicianTimeOff(id, technicianID, createdByUserID, startsAt, endsAt, reason, createdAt)
	if err != nil {
		return TechnicianTimeOff{}, err
	}
	item.updatedAt = updatedAt.UTC()
	return item, nil
}

func (t TechnicianTimeOff) Update(startsAt, endsAt time.Time, reason *string, now time.Time) (TechnicianTimeOff, error) {
	updated, err := NewTechnicianTimeOff(t.id, t.technicianID, t.createdByUserID, startsAt, endsAt, reason, t.createdAt)
	if err != nil {
		return TechnicianTimeOff{}, err
	}
	updated.updatedAt = now.UTC()
	return updated, nil
}

func (t TechnicianTimeOff) ID() uuid.UUID              { return t.id }
func (t TechnicianTimeOff) TechnicianID() uuid.UUID    { return t.technicianID }
func (t TechnicianTimeOff) CreatedByUserID() uuid.UUID { return t.createdByUserID }
func (t TechnicianTimeOff) StartsAt() time.Time        { return t.startsAt }
func (t TechnicianTimeOff) EndsAt() time.Time          { return t.endsAt }
func (t TechnicianTimeOff) Reason() *string            { return t.reason }
func (t TechnicianTimeOff) CreatedAt() time.Time       { return t.createdAt }
func (t TechnicianTimeOff) UpdatedAt() time.Time       { return t.updatedAt }
