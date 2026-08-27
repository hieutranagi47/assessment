package domain

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrServiceBayIDRequired   = errors.New("service bay ID is required")
	ErrServiceBayCodeRequired = errors.New("service bay code is required")
	ErrServiceBayNameRequired = errors.New("service bay name is required")
)

// ServiceBay is an appointment workspace owned by one dealership.
type ServiceBay struct {
	id, dealershipID     uuid.UUID
	code, name           string
	isActive             bool
	createdAt, updatedAt time.Time
}

func NewServiceBay(id, dealershipID uuid.UUID, code, name string, isActive bool, now time.Time) (ServiceBay, error) {
	if id == uuid.Nil {
		return ServiceBay{}, ErrServiceBayIDRequired
	}
	if dealershipID == uuid.Nil {
		return ServiceBay{}, ErrDealershipIDRequired
	}
	code, name, err := validateServiceBay(code, name)
	if err != nil {
		return ServiceBay{}, err
	}
	now = now.UTC()
	return ServiceBay{id: id, dealershipID: dealershipID, code: code, name: name, isActive: isActive, createdAt: now, updatedAt: now}, nil
}

func RehydrateServiceBay(id, dealershipID uuid.UUID, code, name string, isActive bool, createdAt, updatedAt time.Time) (ServiceBay, error) {
	serviceBay, err := NewServiceBay(id, dealershipID, code, name, isActive, createdAt)
	if err != nil {
		return ServiceBay{}, err
	}
	serviceBay.updatedAt = updatedAt.UTC()
	return serviceBay, nil
}

func (s ServiceBay) Update(code, name string, isActive bool, now time.Time) (ServiceBay, error) {
	code, name, err := validateServiceBay(code, name)
	if err != nil {
		return ServiceBay{}, err
	}
	s.code = code
	s.name = name
	s.isActive = isActive
	s.updatedAt = now.UTC()
	return s, nil
}

func validateServiceBay(code, name string) (string, string, error) {
	code = strings.TrimSpace(code)
	if code == "" {
		return "", "", ErrServiceBayCodeRequired
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return "", "", ErrServiceBayNameRequired
	}
	return code, name, nil
}

func (s ServiceBay) ID() uuid.UUID           { return s.id }
func (s ServiceBay) DealershipID() uuid.UUID { return s.dealershipID }
func (s ServiceBay) Code() string            { return s.code }
func (s ServiceBay) Name() string            { return s.name }
func (s ServiceBay) IsActive() bool          { return s.isActive }
func (s ServiceBay) CreatedAt() time.Time    { return s.createdAt }
func (s ServiceBay) UpdatedAt() time.Time    { return s.updatedAt }
