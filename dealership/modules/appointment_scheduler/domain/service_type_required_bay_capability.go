package domain

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrServiceTypeRequiredBayCapabilityIDRequired = errors.New("service type required bay capability ID is required")
	ErrBayCapabilityIDRequired                    = errors.New("bay capability ID is required")
)

// ServiceTypeRequiredBayCapability associates a service type with one item in
// the normalized bay capability catalog.
type ServiceTypeRequiredBayCapability struct {
	id, serviceTypeID, bayCapabilityID uuid.UUID
	capabilityCode, capabilityName     string
	createdAt, updatedAt               time.Time
}

func NewServiceTypeRequiredBayCapability(id, serviceTypeID, bayCapabilityID uuid.UUID, now time.Time) (ServiceTypeRequiredBayCapability, error) {
	if id == uuid.Nil {
		return ServiceTypeRequiredBayCapability{}, ErrServiceTypeRequiredBayCapabilityIDRequired
	}
	if serviceTypeID == uuid.Nil {
		return ServiceTypeRequiredBayCapability{}, ErrServiceTypeIDRequired
	}
	if bayCapabilityID == uuid.Nil {
		return ServiceTypeRequiredBayCapability{}, ErrBayCapabilityIDRequired
	}
	now = now.UTC()
	return ServiceTypeRequiredBayCapability{id: id, serviceTypeID: serviceTypeID, bayCapabilityID: bayCapabilityID, createdAt: now, updatedAt: now}, nil
}

func RehydrateServiceTypeRequiredBayCapability(id, serviceTypeID, bayCapabilityID uuid.UUID, capabilityCode, capabilityName string, createdAt, updatedAt time.Time) (ServiceTypeRequiredBayCapability, error) {
	requiredCapability, err := NewServiceTypeRequiredBayCapability(id, serviceTypeID, bayCapabilityID, createdAt)
	if err != nil {
		return ServiceTypeRequiredBayCapability{}, err
	}
	requiredCapability.capabilityCode = strings.TrimSpace(capabilityCode)
	requiredCapability.capabilityName = strings.TrimSpace(capabilityName)
	requiredCapability.updatedAt = updatedAt.UTC()
	return requiredCapability, nil
}

func (s ServiceTypeRequiredBayCapability) WithBayCapability(bayCapabilityID uuid.UUID, now time.Time) (ServiceTypeRequiredBayCapability, error) {
	if bayCapabilityID == uuid.Nil {
		return ServiceTypeRequiredBayCapability{}, ErrBayCapabilityIDRequired
	}
	s.bayCapabilityID = bayCapabilityID
	s.capabilityCode = ""
	s.capabilityName = ""
	s.updatedAt = now.UTC()
	return s, nil
}

func (s ServiceTypeRequiredBayCapability) ID() uuid.UUID              { return s.id }
func (s ServiceTypeRequiredBayCapability) ServiceTypeID() uuid.UUID   { return s.serviceTypeID }
func (s ServiceTypeRequiredBayCapability) BayCapabilityID() uuid.UUID { return s.bayCapabilityID }
func (s ServiceTypeRequiredBayCapability) CapabilityCode() string     { return s.capabilityCode }
func (s ServiceTypeRequiredBayCapability) CapabilityName() string     { return s.capabilityName }
func (s ServiceTypeRequiredBayCapability) CreatedAt() time.Time       { return s.createdAt }
func (s ServiceTypeRequiredBayCapability) UpdatedAt() time.Time       { return s.updatedAt }
