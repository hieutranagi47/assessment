package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestServiceBayLifecycle(t *testing.T) {
	now := time.Date(2026, 1, 2, 3, 4, 5, 0, time.FixedZone("ICT", 7*60*60))
	bay, err := NewServiceBay(uuid.New(), uuid.New(), " B-01 ", " Main bay ", true, now)
	require.NoError(t, err)
	require.Equal(t, "B-01", bay.Code())
	require.Equal(t, "Main bay", bay.Name())
	require.True(t, bay.IsActive())
	updated, err := bay.Update("B-02", "Secondary", false, now.Add(time.Hour))
	require.NoError(t, err)
	require.Equal(t, "B-02", updated.Code())
	require.False(t, updated.IsActive())
	rehydrated, err := RehydrateServiceBay(bay.ID(), bay.DealershipID(), "B-03", "Restored", true, now, now.Add(2*time.Hour))
	require.NoError(t, err)
	require.Equal(t, now.Add(2*time.Hour).UTC(), rehydrated.UpdatedAt())
	_, err = NewServiceBay(uuid.Nil, uuid.New(), "B", "Bay", true, now)
	require.ErrorIs(t, err, ErrServiceBayIDRequired)
	_, err = bay.Update(" ", "Bay", true, now)
	require.ErrorIs(t, err, ErrServiceBayCodeRequired)
	_, err = bay.Update("B", " ", true, now)
	require.ErrorIs(t, err, ErrServiceBayNameRequired)
}

func TestServiceTypeLifecycleAndValidation(t *testing.T) {
	now := time.Now()
	serviceType, err := NewServiceType(uuid.New(), uuid.New(), " Oil change ", 60, 30, 90, true, now)
	require.NoError(t, err)
	require.Equal(t, "Oil change", serviceType.Name())
	updated, err := serviceType.Update("Repair", 120, 60, 180, false, now.Add(time.Hour))
	require.NoError(t, err)
	require.Equal(t, 120, updated.DefaultDurationMinutes())
	require.False(t, updated.IsActive())
	_, err = NewServiceType(uuid.New(), uuid.New(), "", 60, 30, 90, true, now)
	require.ErrorIs(t, err, ErrServiceTypeNameRequired)
	_, err = NewServiceType(uuid.New(), uuid.New(), "Service", 0, 30, 90, true, now)
	require.ErrorIs(t, err, ErrDurationMustBePositive)
	_, err = NewServiceType(uuid.New(), uuid.New(), "Service", 30, 60, 90, true, now)
	require.ErrorIs(t, err, ErrDurationRangeInvalid)
}

func TestSkillAndCapabilityAssociations(t *testing.T) {
	now := time.Now()
	skill, err := NewTechnicianSkill(uuid.New(), uuid.New(), uuid.New(), now)
	require.NoError(t, err)
	updatedSkill, err := skill.WithSkill(uuid.New(), now.Add(time.Hour))
	require.NoError(t, err)
	require.Equal(t, now.Add(time.Hour).UTC(), updatedSkill.UpdatedAt())
	_, err = skill.WithSkill(uuid.Nil, now)
	require.ErrorIs(t, err, ErrSkillIDRequired)

	bayCapability, err := NewServiceBayCapability(uuid.New(), uuid.New(), uuid.New(), now)
	require.NoError(t, err)
	rehydratedCapability, err := RehydrateServiceBayCapability(bayCapability.ID(), bayCapability.ServiceBayID(), bayCapability.BayCapabilityID(), " CAP ", " Capability ", now, now.Add(time.Hour))
	require.NoError(t, err)
	updatedCapability, err := rehydratedCapability.WithBayCapability(uuid.New(), now.Add(2*time.Hour))
	require.NoError(t, err)
	require.Empty(t, updatedCapability.CapabilityCode())
	require.Empty(t, updatedCapability.CapabilityName())

	requiredSkill, err := NewServiceTypeRequiredSkill(uuid.New(), uuid.New(), uuid.New(), now)
	require.NoError(t, err)
	_, err = requiredSkill.WithSkill(uuid.Nil, now)
	require.ErrorIs(t, err, ErrSkillIDRequired)
	requiredCapability, err := NewServiceTypeRequiredBayCapability(uuid.New(), uuid.New(), uuid.New(), now)
	require.NoError(t, err)
	_, err = requiredCapability.WithBayCapability(uuid.Nil, now)
	require.ErrorIs(t, err, ErrBayCapabilityIDRequired)
}
