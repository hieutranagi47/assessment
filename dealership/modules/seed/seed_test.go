package seed

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestFixtureBayCapabilityAssignmentSupportsFiveConcurrentAppointments(t *testing.T) {
	for capabilityIndex := range capabilities {
		compatibleBays := 0
		for bayIndex := 0; bayIndex < 7; bayIndex++ {
			if fixtureBaySupportsCapability(bayIndex, capabilityIndex) {
				compatibleBays++
			}
		}

		require.Equal(t, 5, compatibleBays, "capability %q", capabilities[capabilityIndex])
	}
}

func TestFixtureBayCapabilityAssignmentKeepsBayProfilesDistinct(t *testing.T) {
	profiles := make(map[string]struct{}, 7)
	for bayIndex := 0; bayIndex < 7; bayIndex++ {
		profile := make([]byte, len(capabilities))
		for capabilityIndex := range capabilities {
			if fixtureBaySupportsCapability(bayIndex, capabilityIndex) {
				profile[capabilityIndex] = '1'
			} else {
				profile[capabilityIndex] = '0'
			}
		}
		profiles[string(profile)] = struct{}{}
	}

	require.Len(t, profiles, 7)
}
