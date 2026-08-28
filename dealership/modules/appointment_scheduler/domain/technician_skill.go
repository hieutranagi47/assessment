package domain

import (
	"errors"
	"time"

	"github.com/google/uuid"
)

var ErrTechnicianSkillIDRequired = errors.New("technician skill ID is required")

// TechnicianSkill assigns one catalog skill to an active technician.
type TechnicianSkill struct {
	id, technicianID, skillID uuid.UUID
	createdAt, updatedAt      time.Time
}

func NewTechnicianSkill(id, technicianID, skillID uuid.UUID, now time.Time) (TechnicianSkill, error) {
	if id == uuid.Nil {
		return TechnicianSkill{}, ErrTechnicianSkillIDRequired
	}
	if technicianID == uuid.Nil {
		return TechnicianSkill{}, ErrTechnicianIDRequired
	}
	if skillID == uuid.Nil {
		return TechnicianSkill{}, ErrSkillIDRequired
	}
	now = now.UTC()
	return TechnicianSkill{id: id, technicianID: technicianID, skillID: skillID, createdAt: now, updatedAt: now}, nil
}

func RehydrateTechnicianSkill(id, technicianID, skillID uuid.UUID, createdAt, updatedAt time.Time) (TechnicianSkill, error) {
	skill, err := NewTechnicianSkill(id, technicianID, skillID, createdAt)
	if err != nil {
		return TechnicianSkill{}, err
	}
	skill.updatedAt = updatedAt.UTC()
	return skill, nil
}

func (s TechnicianSkill) WithSkill(skillID uuid.UUID, now time.Time) (TechnicianSkill, error) {
	if skillID == uuid.Nil {
		return TechnicianSkill{}, ErrSkillIDRequired
	}
	s.skillID = skillID
	s.updatedAt = now.UTC()
	return s, nil
}

func (s TechnicianSkill) ID() uuid.UUID           { return s.id }
func (s TechnicianSkill) TechnicianID() uuid.UUID { return s.technicianID }
func (s TechnicianSkill) SkillID() uuid.UUID      { return s.skillID }
func (s TechnicianSkill) CreatedAt() time.Time    { return s.createdAt }
func (s TechnicianSkill) UpdatedAt() time.Time    { return s.updatedAt }
