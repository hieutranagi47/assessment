package app

import (
	"context"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/domain"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type vehicleRepositoryStub struct {
	dealershipID uuid.UUID
	customers    map[uuid.UUID]domain.Customer
	vehicles     map[uuid.UUID]domain.Vehicle
	owners       map[uuid.UUID]uuid.UUID
}

func (r *vehicleRepositoryStub) Create(context.Context, domain.Dealership) error { return nil }
func (r *vehicleRepositoryStub) GetActiveVehicleManagerDealership(context.Context, uuid.UUID) (uuid.UUID, error) {
	if r.dealershipID == uuid.Nil {
		return uuid.Nil, ErrVehicleCustomerForbidden
	}
	return r.dealershipID, nil
}
func (r *vehicleRepositoryStub) GetCustomer(_ context.Context, id uuid.UUID) (domain.Customer, error) {
	customer, ok := r.customers[id]
	if !ok {
		return domain.Customer{}, ErrCustomerNotFound
	}
	return customer, nil
}
func (r *vehicleRepositoryStub) CreateVehicle(_ context.Context, dealershipID uuid.UUID, vehicle domain.Vehicle) error {
	if _, ok := r.customers[vehicle.CustomerID()]; !ok {
		return ErrCustomerNotFound
	}
	if owner, ok := r.owners[vehicle.CustomerID()]; ok && owner != dealershipID {
		return ErrVehicleCustomerForbidden
	}
	for _, existing := range r.vehicles {
		if existing.VIN() != nil && vehicle.VIN() != nil && *existing.VIN() == *vehicle.VIN() {
			return ErrVehicleVINTaken
		}
	}
	r.owners[vehicle.CustomerID()] = dealershipID
	r.vehicles[vehicle.ID()] = vehicle
	return nil
}
func (r *vehicleRepositoryStub) GetVehicle(_ context.Context, id uuid.UUID) (domain.Vehicle, error) {
	vehicle, ok := r.vehicles[id]
	if !ok {
		return domain.Vehicle{}, ErrVehicleNotFound
	}
	return vehicle, nil
}
func (r *vehicleRepositoryStub) ListCustomerVehicles(_ context.Context, customerID uuid.UUID) ([]domain.Vehicle, error) {
	items := []domain.Vehicle{}
	for _, vehicle := range r.vehicles {
		if vehicle.CustomerID() == customerID {
			items = append(items, vehicle)
		}
	}
	return items, nil
}
func (r *vehicleRepositoryStub) CustomerBelongsToDealership(_ context.Context, customerID, dealershipID uuid.UUID) (bool, error) {
	return r.owners[customerID] == dealershipID, nil
}
func (r *vehicleRepositoryStub) UpdateVehicle(_ context.Context, vehicle domain.Vehicle) error {
	if _, ok := r.vehicles[vehicle.ID()]; !ok {
		return ErrVehicleNotFound
	}
	r.vehicles[vehicle.ID()] = vehicle
	return nil
}
func (r *vehicleRepositoryStub) DeleteVehicle(_ context.Context, id uuid.UUID, _ time.Time) error {
	if _, ok := r.vehicles[id]; !ok {
		return ErrVehicleNotFound
	}
	delete(r.vehicles, id)
	return nil
}

func TestVehicleCRUDEnforcesDealershipOwnershipAndVINUniqueness(t *testing.T) {
	dealershipID := uuid.New()
	customerID := uuid.New()
	customer := domain.RestoreCustomer(customerID, "Jane Doe", "+84901234567", nil, time.Now(), time.Now())
	repository := &vehicleRepositoryStub{dealershipID: dealershipID, customers: map[uuid.UUID]domain.Customer{customerID: customer}, vehicles: map[uuid.UUID]domain.Vehicle{}, owners: map[uuid.UUID]uuid.UUID{}}
	service := NewService(repository, customerUserInfoStub{})
	service.now = func() time.Time { return time.Date(2026, 8, 28, 0, 0, 0, 0, time.UTC) }

	vin := " 1hgcm82633a004352 "
	vehicle, err := service.CreateVehicle(context.Background(), uuid.New(), customerID, CreateVehicleInput{VIN: &vin, Make: " Toyota ", Model: " Camry "})
	require.NoError(t, err)
	require.Equal(t, "1HGCM82633A004352", *vehicle.VIN())
	_, err = service.CreateVehicle(context.Background(), uuid.New(), customerID, CreateVehicleInput{VIN: &vin, Make: "Toyota", Model: "Camry"})
	require.ErrorContains(t, err, "vehicle_vin_already_exists")

	repository.dealershipID = uuid.New()
	_, err = service.GetVehicle(context.Background(), uuid.New(), vehicle.ID())
	require.ErrorContains(t, err, "vehicle_access_forbidden")

	repository.dealershipID = dealershipID
	updated, err := service.UpdateVehicle(context.Background(), uuid.New(), vehicle.ID(), UpdateVehicleInput{Make: stringPointer("Honda")})
	require.NoError(t, err)
	require.Equal(t, "Honda", updated.Make())
	require.NoError(t, service.DeleteVehicle(context.Background(), uuid.New(), vehicle.ID()))
}

func stringPointer(value string) *string { return &value }
