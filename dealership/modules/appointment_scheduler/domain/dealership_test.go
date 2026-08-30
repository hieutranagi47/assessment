package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestNewDealershipNormalizesAndExposesState(t *testing.T) {
	now := time.Date(2026, 1, 2, 3, 4, 5, 0, time.FixedZone("ICT", 7*60*60))
	dealership, err := NewDealership(uuid.New(), "  Downtown Motors ", " hcm-01 ", " 1 Main Street ", " Asia/Ho_Chi_Minh ", now)
	require.NoError(t, err)
	require.Equal(t, "Downtown Motors", dealership.Name())
	require.Equal(t, "HCM-01", dealership.Code())
	require.Equal(t, "1 Main Street", dealership.Address())
	require.Equal(t, "Asia/Ho_Chi_Minh", dealership.Timezone())
	require.True(t, dealership.IsActive())
	require.Equal(t, now.UTC(), dealership.CreatedAt())
	require.Equal(t, now.UTC(), dealership.UpdatedAt())
}

func TestNewDealershipValidatesRequiredFields(t *testing.T) {
	validID := uuid.New()
	cases := []struct {
		label, name, code, address, timezone string
		want                                 error
	}{
		{"missing ID", "name", "code", "address", "UTC", nil},
		{"missing name", " ", "code", "address", "UTC", ErrNameRequired},
		{"missing code", "name", " ", "address", "UTC", ErrCodeRequired},
		{"missing address", "name", "code", " ", "UTC", ErrAddressRequired},
		{"missing timezone", "name", "code", "address", " ", ErrTimezoneRequired},
		{"invalid timezone", "name", "code", "address", "Mars/Olympus", ErrInvalidTimezone},
	}
	for _, tc := range cases {
		t.Run(tc.label, func(t *testing.T) {
			id := validID
			if tc.label == "missing ID" {
				id = uuid.Nil
			}
			_, err := NewDealership(id, tc.name, tc.code, tc.address, tc.timezone, time.Now())
			require.Error(t, err)
			if tc.want != nil {
				require.ErrorIs(t, err, tc.want)
			}
		})
	}
}
