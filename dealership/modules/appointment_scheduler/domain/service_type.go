package domain

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrServiceTypeIDRequired   = errors.New("service type ID is required")
	ErrServiceTypeNameRequired = errors.New("service type name is required")
	ErrDurationMustBePositive  = errors.New("service type durations must be positive")
	ErrDurationRangeInvalid    = errors.New("minimum, default, and maximum durations must be ordered")
)

// ServiceType describes an appointment service offered by one dealership.
type ServiceType struct {
	id, dealershipID                                               uuid.UUID
	name                                                           string
	defaultDurationMinutes, minDurationMinutes, maxDurationMinutes int
	isActive                                                       bool
	createdAt, updatedAt                                           time.Time
}

func NewServiceType(
	id, dealershipID uuid.UUID,
	name string,
	defaultDurationMinutes, minDurationMinutes, maxDurationMinutes int,
	isActive bool,
	now time.Time,
) (ServiceType, error) {
	if id == uuid.Nil {
		return ServiceType{}, ErrServiceTypeIDRequired
	}
	if dealershipID == uuid.Nil {
		return ServiceType{}, ErrDealershipIDRequired
	}
	name, err := validateServiceType(name, defaultDurationMinutes, minDurationMinutes, maxDurationMinutes)
	if err != nil {
		return ServiceType{}, err
	}
	now = now.UTC()
	return ServiceType{
		id: id, dealershipID: dealershipID, name: name,
		defaultDurationMinutes: defaultDurationMinutes,
		minDurationMinutes:     minDurationMinutes,
		maxDurationMinutes:     maxDurationMinutes,
		isActive:               isActive,
		createdAt:              now,
		updatedAt:              now,
	}, nil
}

func RehydrateServiceType(
	id, dealershipID uuid.UUID,
	name string,
	defaultDurationMinutes, minDurationMinutes, maxDurationMinutes int,
	isActive bool,
	createdAt, updatedAt time.Time,
) (ServiceType, error) {
	serviceType, err := NewServiceType(id, dealershipID, name, defaultDurationMinutes, minDurationMinutes, maxDurationMinutes, isActive, createdAt)
	if err != nil {
		return ServiceType{}, err
	}
	serviceType.updatedAt = updatedAt.UTC()
	return serviceType, nil
}

func (s ServiceType) Update(
	name string,
	defaultDurationMinutes, minDurationMinutes, maxDurationMinutes int,
	isActive bool,
	now time.Time,
) (ServiceType, error) {
	name, err := validateServiceType(name, defaultDurationMinutes, minDurationMinutes, maxDurationMinutes)
	if err != nil {
		return ServiceType{}, err
	}
	s.name = name
	s.defaultDurationMinutes = defaultDurationMinutes
	s.minDurationMinutes = minDurationMinutes
	s.maxDurationMinutes = maxDurationMinutes
	s.isActive = isActive
	s.updatedAt = now.UTC()
	return s, nil
}

func validateServiceType(name string, defaultDurationMinutes, minDurationMinutes, maxDurationMinutes int) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", ErrServiceTypeNameRequired
	}
	if defaultDurationMinutes <= 0 || minDurationMinutes <= 0 || maxDurationMinutes <= 0 {
		return "", ErrDurationMustBePositive
	}
	if minDurationMinutes > defaultDurationMinutes || defaultDurationMinutes > maxDurationMinutes {
		return "", ErrDurationRangeInvalid
	}
	return name, nil
}

func (s ServiceType) ID() uuid.UUID               { return s.id }
func (s ServiceType) DealershipID() uuid.UUID     { return s.dealershipID }
func (s ServiceType) Name() string                { return s.name }
func (s ServiceType) DefaultDurationMinutes() int { return s.defaultDurationMinutes }
func (s ServiceType) MinDurationMinutes() int     { return s.minDurationMinutes }
func (s ServiceType) MaxDurationMinutes() int     { return s.maxDurationMinutes }
func (s ServiceType) IsActive() bool              { return s.isActive }
func (s ServiceType) CreatedAt() time.Time        { return s.createdAt }
func (s ServiceType) UpdatedAt() time.Time        { return s.updatedAt }
