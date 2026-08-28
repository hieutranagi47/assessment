package domain

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

var ErrServiceBayCapabilityIDRequired = errors.New("service bay capability ID is required")

// ServiceBayCapability records one global catalog capability assigned to a
// dealership-owned service bay.
type ServiceBayCapability struct {
	id, serviceBayID, bayCapabilityID uuid.UUID
	capabilityCode, capabilityName    string
	createdAt, updatedAt              time.Time
}

func NewServiceBayCapability(id, serviceBayID, bayCapabilityID uuid.UUID, now time.Time) (ServiceBayCapability, error) {
	if id == uuid.Nil {
		return ServiceBayCapability{}, ErrServiceBayCapabilityIDRequired
	}
	if serviceBayID == uuid.Nil {
		return ServiceBayCapability{}, ErrServiceBayIDRequired
	}
	if bayCapabilityID == uuid.Nil {
		return ServiceBayCapability{}, ErrBayCapabilityIDRequired
	}
	now = now.UTC()
	return ServiceBayCapability{id: id, serviceBayID: serviceBayID, bayCapabilityID: bayCapabilityID, createdAt: now, updatedAt: now}, nil
}

func RehydrateServiceBayCapability(id, serviceBayID, bayCapabilityID uuid.UUID, capabilityCode, capabilityName string, createdAt, updatedAt time.Time) (ServiceBayCapability, error) {
	capability, err := NewServiceBayCapability(id, serviceBayID, bayCapabilityID, createdAt)
	if err != nil {
		return ServiceBayCapability{}, err
	}
	capability.capabilityCode = strings.TrimSpace(capabilityCode)
	capability.capabilityName = strings.TrimSpace(capabilityName)
	capability.updatedAt = updatedAt.UTC()
	return capability, nil
}

func (s ServiceBayCapability) WithBayCapability(bayCapabilityID uuid.UUID, now time.Time) (ServiceBayCapability, error) {
	if bayCapabilityID == uuid.Nil {
		return ServiceBayCapability{}, ErrBayCapabilityIDRequired
	}
	s.bayCapabilityID = bayCapabilityID
	s.capabilityCode = ""
	s.capabilityName = ""
	s.updatedAt = now.UTC()
	return s, nil
}

func (s ServiceBayCapability) ID() uuid.UUID              { return s.id }
func (s ServiceBayCapability) ServiceBayID() uuid.UUID    { return s.serviceBayID }
func (s ServiceBayCapability) BayCapabilityID() uuid.UUID { return s.bayCapabilityID }
func (s ServiceBayCapability) CapabilityCode() string     { return s.capabilityCode }
func (s ServiceBayCapability) CapabilityName() string     { return s.capabilityName }
func (s ServiceBayCapability) CreatedAt() time.Time       { return s.createdAt }
func (s ServiceBayCapability) UpdatedAt() time.Time       { return s.updatedAt }
