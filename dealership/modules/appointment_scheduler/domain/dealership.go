// Package domain contains the dealership business model and its invariants.
package domain

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrNameRequired     = errors.New("dealership name is required")
	ErrCodeRequired     = errors.New("dealership code is required")
	ErrAddressRequired  = errors.New("dealership address is required")
	ErrTimezoneRequired = errors.New("dealership timezone is required")
	ErrInvalidTimezone  = errors.New("dealership timezone must be a valid IANA timezone")
)

// Dealership is the aggregate persisted by the dealership module.
type Dealership struct {
	id                            uuid.UUID
	name, code, address, timezone string
	isActive                      bool
	createdAt, updatedAt          time.Time
}

// NewDealership validates and normalizes a dealership before it is persisted.
func NewDealership(id uuid.UUID, name, code, address, timezone string, now time.Time) (Dealership, error) {
	if id == uuid.Nil {
		return Dealership{}, errors.New("dealership ID is required")
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return Dealership{}, ErrNameRequired
	}
	code = strings.ToUpper(strings.TrimSpace(code))
	if code == "" {
		return Dealership{}, ErrCodeRequired
	}
	address = strings.TrimSpace(address)
	if address == "" {
		return Dealership{}, ErrAddressRequired
	}
	timezone = strings.TrimSpace(timezone)
	if timezone == "" {
		return Dealership{}, ErrTimezoneRequired
	}
	if _, err := time.LoadLocation(timezone); err != nil {
		return Dealership{}, ErrInvalidTimezone
	}
	now = now.UTC()
	return Dealership{
		id:        id,
		name:      name,
		code:      code,
		address:   address,
		timezone:  timezone,
		isActive:  true,
		createdAt: now,
		updatedAt: now,
	}, nil
}

// RehydrateDealership rebuilds a persisted dealership while preserving its
// lifecycle state and timestamps.
func RehydrateDealership(id uuid.UUID, name, code, address, timezone string, isActive bool, createdAt, updatedAt time.Time) (Dealership, error) {
	dealership, err := NewDealership(id, name, code, address, timezone, createdAt)
	if err != nil {
		return Dealership{}, err
	}
	dealership.isActive = isActive
	dealership.updatedAt = updatedAt.UTC()
	return dealership, nil
}

func (d Dealership) ID() uuid.UUID        { return d.id }
func (d Dealership) Name() string         { return d.name }
func (d Dealership) Code() string         { return d.code }
func (d Dealership) Address() string      { return d.address }
func (d Dealership) Timezone() string     { return d.timezone }
func (d Dealership) IsActive() bool       { return d.isActive }
func (d Dealership) CreatedAt() time.Time { return d.createdAt }
func (d Dealership) UpdatedAt() time.Time { return d.updatedAt }
