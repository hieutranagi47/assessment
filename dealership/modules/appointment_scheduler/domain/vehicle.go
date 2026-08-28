package domain

import (
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrVehicleMakeRequired  = errors.New("vehicle make is required")
	ErrVehicleModelRequired = errors.New("vehicle model is required")
	ErrVehicleIdentity      = errors.New("vehicle VIN or registration plate is required")
	ErrVehicleModelYear     = errors.New("vehicle model year is invalid")
)

// Vehicle owns its normalized, valid identity and descriptive data.
type Vehicle struct {
	id                uuid.UUID
	customerID        uuid.UUID
	vin               *string
	registrationPlate *string
	make              string
	model             string
	modelYear         *int
	createdAt         time.Time
	updatedAt         time.Time
}

func NewVehicle(id, customerID uuid.UUID, vin, registrationPlate *string, make, model string, modelYear *int, now time.Time) (Vehicle, error) {
	if id == uuid.Nil || customerID == uuid.Nil {
		return Vehicle{}, errors.New("vehicle and customer IDs are required")
	}
	vehicle := Vehicle{id: id, customerID: customerID, vin: normalizeVehicleIdentifier(vin), registrationPlate: normalizeVehicleIdentifier(registrationPlate), make: strings.TrimSpace(make), model: strings.TrimSpace(model), modelYear: copyInt(modelYear), createdAt: now, updatedAt: now}
	if err := vehicle.validate(); err != nil {
		return Vehicle{}, err
	}
	return vehicle, nil
}

func RestoreVehicle(id, customerID uuid.UUID, vin, registrationPlate *string, make, model string, modelYear *int, createdAt, updatedAt time.Time) Vehicle {
	return Vehicle{id: id, customerID: customerID, vin: copyString(vin), registrationPlate: copyString(registrationPlate), make: make, model: model, modelYear: copyInt(modelYear), createdAt: createdAt, updatedAt: updatedAt}
}

func (v Vehicle) ID() uuid.UUID              { return v.id }
func (v Vehicle) CustomerID() uuid.UUID      { return v.customerID }
func (v Vehicle) VIN() *string               { return copyString(v.vin) }
func (v Vehicle) RegistrationPlate() *string { return copyString(v.registrationPlate) }
func (v Vehicle) Make() string               { return v.make }
func (v Vehicle) Model() string              { return v.model }
func (v Vehicle) ModelYear() *int            { return copyInt(v.modelYear) }
func (v Vehicle) CreatedAt() time.Time       { return v.createdAt }
func (v Vehicle) UpdatedAt() time.Time       { return v.updatedAt }

func (v Vehicle) Update(vin, registrationPlate *string, make, model string, modelYear *int, now time.Time) (Vehicle, error) {
	v.vin = normalizeVehicleIdentifier(vin)
	v.registrationPlate = normalizeVehicleIdentifier(registrationPlate)
	v.make = strings.TrimSpace(make)
	v.model = strings.TrimSpace(model)
	v.modelYear = copyInt(modelYear)
	if err := v.validate(); err != nil {
		return Vehicle{}, err
	}
	v.updatedAt = now
	return v, nil
}

func (v Vehicle) validate() error {
	if v.make == "" {
		return ErrVehicleMakeRequired
	}
	if v.model == "" {
		return ErrVehicleModelRequired
	}
	if v.vin == nil && v.registrationPlate == nil {
		return ErrVehicleIdentity
	}
	if v.vin != nil && len(*v.vin) > 17 {
		return ErrVehicleIdentity
	}
	if v.registrationPlate != nil && len(*v.registrationPlate) > 32 {
		return ErrVehicleIdentity
	}
	if v.modelYear != nil && (*v.modelYear < 1886 || *v.modelYear > 2100) {
		return ErrVehicleModelYear
	}
	return nil
}

func normalizeVehicleIdentifier(value *string) *string {
	if value == nil {
		return nil
	}
	normalized := strings.ToUpper(strings.TrimSpace(*value))
	if normalized == "" {
		return nil
	}
	return &normalized
}

func copyInt(value *int) *int {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}
