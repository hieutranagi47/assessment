package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestVehicleNormalizesAndValidatesItsState(t *testing.T) {
	vin := "  1hgcm82633a004352 "
	plate := "  51a-123.45 "
	year := 2024
	vehicle, err := NewVehicle(uuid.New(), uuid.New(), &vin, &plate, " Toyota ", " Camry ", &year, time.Now())
	require.NoError(t, err)
	require.Equal(t, "1HGCM82633A004352", *vehicle.VIN())
	require.Equal(t, "51A-123.45", *vehicle.RegistrationPlate())
	require.Equal(t, "Toyota", vehicle.Make())
	require.Equal(t, "Camry", vehicle.Model())

	_, err = NewVehicle(uuid.New(), uuid.New(), nil, nil, "Toyota", "Camry", nil, time.Now())
	require.ErrorIs(t, err, ErrVehicleIdentity)
	invalidYear := 1800
	_, err = NewVehicle(uuid.New(), uuid.New(), &vin, nil, "Toyota", "Camry", &invalidYear, time.Now())
	require.ErrorIs(t, err, ErrVehicleModelYear)
}
