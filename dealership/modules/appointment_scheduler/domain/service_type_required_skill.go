package domain

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrServiceTypeRequiredSkillIDRequired = errors.New("service type required skill ID is required")
	ErrSkillIDRequired                    = errors.New("skill ID is required")
)

// ServiceTypeRequiredSkill is a normalized skill association for one service type.
type ServiceTypeRequiredSkill struct {
	id, serviceTypeID, skillID uuid.UUID
	skillCode, skillName       string
	createdAt, updatedAt       time.Time
}

func NewServiceTypeRequiredSkill(id, serviceTypeID, skillID uuid.UUID, now time.Time) (ServiceTypeRequiredSkill, error) {
	if id == uuid.Nil {
		return ServiceTypeRequiredSkill{}, ErrServiceTypeRequiredSkillIDRequired
	}
	if serviceTypeID == uuid.Nil {
		return ServiceTypeRequiredSkill{}, ErrServiceTypeIDRequired
	}
	if skillID == uuid.Nil {
		return ServiceTypeRequiredSkill{}, ErrSkillIDRequired
	}
	now = now.UTC()
	return ServiceTypeRequiredSkill{id: id, serviceTypeID: serviceTypeID, skillID: skillID, createdAt: now, updatedAt: now}, nil
}

func RehydrateServiceTypeRequiredSkill(id, serviceTypeID, skillID uuid.UUID, skillCode, skillName string, createdAt, updatedAt time.Time) (ServiceTypeRequiredSkill, error) {
	requiredSkill, err := NewServiceTypeRequiredSkill(id, serviceTypeID, skillID, createdAt)
	if err != nil {
		return ServiceTypeRequiredSkill{}, err
	}
	requiredSkill.skillCode = strings.TrimSpace(skillCode)
	requiredSkill.skillName = strings.TrimSpace(skillName)
	requiredSkill.updatedAt = updatedAt.UTC()
	return requiredSkill, nil
}

func (s ServiceTypeRequiredSkill) WithSkill(skillID uuid.UUID, now time.Time) (ServiceTypeRequiredSkill, error) {
	if skillID == uuid.Nil {
		return ServiceTypeRequiredSkill{}, ErrSkillIDRequired
	}
	s.skillID = skillID
	s.skillCode = ""
	s.skillName = ""
	s.updatedAt = now.UTC()
	return s, nil
}

func (s ServiceTypeRequiredSkill) ID() uuid.UUID            { return s.id }
func (s ServiceTypeRequiredSkill) ServiceTypeID() uuid.UUID { return s.serviceTypeID }
func (s ServiceTypeRequiredSkill) SkillID() uuid.UUID       { return s.skillID }
func (s ServiceTypeRequiredSkill) SkillCode() string        { return s.skillCode }
func (s ServiceTypeRequiredSkill) SkillName() string        { return s.skillName }
func (s ServiceTypeRequiredSkill) CreatedAt() time.Time     { return s.createdAt }
func (s ServiceTypeRequiredSkill) UpdatedAt() time.Time     { return s.updatedAt }
