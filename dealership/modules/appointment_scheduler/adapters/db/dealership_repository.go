package db

import (
	"context"
	"errors"
	"time"

	"assessment/modules/appointment_scheduler/adapters/db/dbmodels"
	"assessment/modules/appointment_scheduler/app"
	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DealershipRepository stores dealership aggregates in PostgreSQL.
type DealershipRepository struct {
	database *pgxpool.Pool
	queries  *dbmodels.Queries
}

func NewDealershipRepository(database *pgxpool.Pool) *DealershipRepository {
	if database == nil {
		panic("appointment scheduler database pool is required")
	}
	return &DealershipRepository{database: database, queries: dbmodels.New(database)}
}

func (r *DealershipRepository) Create(ctx context.Context, dealership domain.Dealership) error {
	id := toPGUUID(dealership.ID())
	err := r.queries.CreateDealerships(ctx, dbmodels.CreateDealershipsParams{
		DealershipID: id,
		Name:         dealership.Name(),
		Code:         dealership.Code(),
		Address:      dealership.Address(),
		Timezone:     dealership.Timezone(),
		IsActive:     dealership.IsActive(),
		CreatedAt:    dealership.CreatedAt(),
		UpdatedAt:    dealership.UpdatedAt(),
	})
	if isDuplicateDealershipCode(err) {
		return app.ErrDealershipCodeTaken
	}
	return err
}

// IsActiveSchedulerAdmin reports whether the auth user has an active
// appointment-scheduler user record with the admin role.
func (r *DealershipRepository) IsActiveSchedulerAdmin(ctx context.Context, authUserID uuid.UUID) (bool, error) {
	return r.queries.IsActiveSchedulerAdmin(ctx, toPGUUID(authUserID))
}

// IsActiveSchedulerAdminForDealership verifies the caller's membership in the
// dealership being changed; scheduler-admin authority is never global.
func (r *DealershipRepository) IsActiveSchedulerAdminForDealership(ctx context.Context, authUserID, dealershipID uuid.UUID) (bool, error) {
	return r.queries.IsActiveSchedulerAdminForDealership(ctx, dbmodels.IsActiveSchedulerAdminForDealershipParams{
		AuthUserID:   toPGUUID(authUserID),
		DealershipID: toPGUUID(dealershipID),
	})
}

func (r *DealershipRepository) IsActiveDealership(ctx context.Context, dealershipID uuid.UUID) (bool, error) {
	_, err := r.queries.GetActiveDealership(ctx, toPGUUID(dealershipID))
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

func (r *DealershipRepository) CanReadAvailableServiceBays(ctx context.Context, authUserID, dealershipID uuid.UUID) (bool, error) {
	return r.queries.CanReadAvailableServiceBays(ctx, dbmodels.CanReadAvailableServiceBaysParams{
		AuthUserID:   toPGUUID(authUserID),
		DealershipID: toPGUUID(dealershipID),
	})
}

func (r *DealershipRepository) ListAvailableServiceBays(ctx context.Context, dealershipID uuid.UUID, startsAt, endsAt time.Time) ([]domain.ServiceBay, error) {
	rows, err := r.queries.ListAvailableServiceBays(ctx, dbmodels.ListAvailableServiceBaysParams{
		DealershipID: toPGUUID(dealershipID),
		StartsAt:     startsAt,
		EndsAt:       endsAt,
	})
	if err != nil {
		return nil, err
	}
	items := make([]domain.ServiceBay, 0, len(rows))
	for _, row := range rows {
		serviceBay, err := domain.RehydrateServiceBay(
			fromPGUUID(row.ServiceBayID),
			fromPGUUID(row.DealershipID),
			row.Code,
			row.Name,
			row.IsActive,
			row.CreatedAt,
			row.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		items = append(items, serviceBay)
	}
	return items, nil
}

var _ app.AvailableServiceBayRepository = (*DealershipRepository)(nil)

func (r *DealershipRepository) CanReadTechnicianSchedules(ctx context.Context, authUserID, dealershipID uuid.UUID) (bool, error) {
	return r.queries.CanReadTechnicianSchedules(ctx, dbmodels.CanReadTechnicianSchedulesParams{
		AuthUserID:   toPGUUID(authUserID),
		DealershipID: toPGUUID(dealershipID),
	})
}

func (r *DealershipRepository) GetActiveTechnicianScheduleDealership(ctx context.Context, dealershipID uuid.UUID) (app.TechnicianScheduleDealership, error) {
	row, err := r.queries.GetActiveTechnicianScheduleDealership(ctx, toPGUUID(dealershipID))
	if errors.Is(err, pgx.ErrNoRows) {
		return app.TechnicianScheduleDealership{}, app.ErrTechnicianScheduleDealershipNotFound
	}
	if err != nil {
		return app.TechnicianScheduleDealership{}, err
	}
	return app.TechnicianScheduleDealership{
		ID:       fromPGUUID(row.DealershipID),
		Timezone: row.Timezone,
	}, nil
}

func (r *DealershipRepository) ListActiveTechniciansForSchedule(ctx context.Context, dealershipID uuid.UUID, technicianID *uuid.UUID) ([]app.TechnicianScheduleTechnician, error) {
	rows, err := r.queries.ListActiveTechniciansForSchedule(ctx, dbmodels.ListActiveTechniciansForScheduleParams{
		DealershipID: toPGUUID(dealershipID),
		TechnicianID: nullablePGUUID(technicianID),
	})
	if err != nil {
		return nil, err
	}
	items := make([]app.TechnicianScheduleTechnician, 0, len(rows))
	for _, row := range rows {
		items = append(items, app.TechnicianScheduleTechnician{
			TechnicianID: fromPGUUID(row.TechnicianID),
			UserID:       fromPGUUID(row.UserID),
			Name:         row.Name,
		})
	}
	return items, nil
}

func (r *DealershipRepository) ListTechnicianScheduleShifts(ctx context.Context, dealershipID uuid.UUID, technicianID *uuid.UUID, dayOfWeek int) ([]app.TechnicianScheduleShift, error) {
	rows, err := r.queries.ListTechnicianScheduleShifts(ctx, dbmodels.ListTechnicianScheduleShiftsParams{
		DealershipID: toPGUUID(dealershipID),
		DayOfWeek:    int16(dayOfWeek),
		TechnicianID: nullablePGUUID(technicianID),
	})
	if err != nil {
		return nil, err
	}
	items := make([]app.TechnicianScheduleShift, 0, len(rows))
	for _, row := range rows {
		items = append(items, app.TechnicianScheduleShift{
			TechnicianID: fromPGUUID(row.TechnicianID),
			StartsAt:     time.Duration(row.StartsAt.Microseconds) * time.Microsecond,
			EndsAt:       time.Duration(row.EndsAt.Microseconds) * time.Microsecond,
		})
	}
	return items, nil
}

func (r *DealershipRepository) ListTechnicianScheduleAppointments(ctx context.Context, dealershipID uuid.UUID, technicianID *uuid.UUID, periodStartsAt, periodEndsAt time.Time) ([]app.TechnicianScheduleAppointment, error) {
	rows, err := r.queries.ListTechnicianScheduleAppointments(ctx, dbmodels.ListTechnicianScheduleAppointmentsParams{
		DealershipID:   toPGUUID(dealershipID),
		PeriodStartsAt: periodStartsAt,
		PeriodEndsAt:   periodEndsAt,
		TechnicianID:   nullablePGUUID(technicianID),
	})
	if err != nil {
		return nil, err
	}
	items := make([]app.TechnicianScheduleAppointment, 0, len(rows))
	for _, row := range rows {
		items = append(items, app.TechnicianScheduleAppointment{
			TechnicianID:    fromPGUUID(row.TechnicianID),
			AppointmentID:   fromPGUUID(row.AppointmentID),
			ReferenceCode:   row.ReferenceCode,
			StartsAt:        row.StartsAt,
			EndsAt:          row.EndsAt,
			Status:          row.Status,
			ServiceTypeName: row.ServiceTypeName,
			ServiceBayID:    fromPGUUID(row.ServiceBayID),
			ServiceBayCode:  row.ServiceBayCode,
		})
	}
	return items, nil
}

func (r *DealershipRepository) ListTechnicianScheduleTimeOff(ctx context.Context, dealershipID uuid.UUID, technicianID *uuid.UUID, periodStartsAt, periodEndsAt time.Time) ([]app.TechnicianScheduleTimeOff, error) {
	rows, err := r.queries.ListTechnicianScheduleTimeOff(ctx, dbmodels.ListTechnicianScheduleTimeOffParams{
		DealershipID:   toPGUUID(dealershipID),
		PeriodStartsAt: periodStartsAt,
		PeriodEndsAt:   periodEndsAt,
		TechnicianID:   nullablePGUUID(technicianID),
	})
	if err != nil {
		return nil, err
	}
	items := make([]app.TechnicianScheduleTimeOff, 0, len(rows))
	for _, row := range rows {
		items = append(items, app.TechnicianScheduleTimeOff{
			TechnicianID: fromPGUUID(row.TechnicianID),
			StartsAt:     row.StartsAt,
			EndsAt:       row.EndsAt,
		})
	}
	return items, nil
}

var _ app.TechnicianScheduleRepository = (*DealershipRepository)(nil)

func (r *DealershipRepository) CreateDealershipOperationTime(ctx context.Context, operationTime domain.DealershipOperationTime) error {
	err := r.queries.CreateDealershipOperationTime(ctx, dbmodels.CreateDealershipOperationTimeParams{
		DealershipOperationTimeID: toPGUUID(operationTime.ID()),
		DealershipID:              toPGUUID(operationTime.DealershipID()),
		DayOfWeek:                 int16(operationTime.DayOfWeek()),
		OpensAt:                   toPGTime(operationTime.OpensAt()),
		ClosesAt:                  toPGTime(operationTime.ClosesAt()),
		CreatedAt:                 operationTime.CreatedAt(),
		UpdatedAt:                 operationTime.UpdatedAt(),
	})
	return operationTimeWriteError(err)
}

func (r *DealershipRepository) GetDealershipOperationTime(ctx context.Context, dealershipID, operationTimeID uuid.UUID) (domain.DealershipOperationTime, error) {
	row, err := r.queries.GetDealershipOperationTime(ctx, dbmodels.GetDealershipOperationTimeParams{DealershipID: toPGUUID(dealershipID), DealershipOperationTimeID: toPGUUID(operationTimeID)})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.DealershipOperationTime{}, app.ErrDealershipOperationTimeNotFound
	}
	if err != nil {
		return domain.DealershipOperationTime{}, err
	}
	return operationTimeFromRow(row)
}

func (r *DealershipRepository) ListDealershipOperationTimes(ctx context.Context, dealershipID uuid.UUID) ([]domain.DealershipOperationTime, error) {
	rows, err := r.queries.ListDealershipOperationTimes(ctx, toPGUUID(dealershipID))
	if err != nil {
		return nil, err
	}
	items := make([]domain.DealershipOperationTime, 0, len(rows))
	for _, row := range rows {
		item, err := operationTimeFromRow(row)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, nil
}

func (r *DealershipRepository) UpdateDealershipOperationTime(ctx context.Context, operationTime domain.DealershipOperationTime) error {
	rows, err := r.queries.UpdateDealershipOperationTime(ctx, dbmodels.UpdateDealershipOperationTimeParams{DealershipID: toPGUUID(operationTime.DealershipID()), DayOfWeek: int16(operationTime.DayOfWeek()), OpensAt: toPGTime(operationTime.OpensAt()), ClosesAt: toPGTime(operationTime.ClosesAt()), UpdatedAt: operationTime.UpdatedAt(), DealershipOperationTimeID: toPGUUID(operationTime.ID())})
	if err = operationTimeWriteError(err); err != nil {
		return err
	}
	if rows == 0 {
		return app.ErrDealershipOperationTimeNotFound
	}
	return nil
}

func (r *DealershipRepository) DeleteDealershipOperationTime(ctx context.Context, dealershipID, operationTimeID uuid.UUID) error {
	rows, err := r.queries.DeleteDealershipOperationTime(ctx, dbmodels.DeleteDealershipOperationTimeParams{DealershipID: toPGUUID(dealershipID), DealershipOperationTimeID: toPGUUID(operationTimeID)})
	if err != nil {
		return err
	}
	if rows == 0 {
		return app.ErrDealershipOperationTimeNotFound
	}
	return nil
}

func (r *DealershipRepository) IsActiveCustomerEmployee(ctx context.Context, authUserID uuid.UUID) (bool, error) {
	if authUserID == uuid.Nil {
		return false, nil
	}
	return r.queries.IsActiveCustomerEmployee(ctx, toPGUUID(authUserID))
}

func (r *DealershipRepository) CreateCustomer(ctx context.Context, customer domain.Customer) (domain.Customer, error) {
	row, err := r.queries.CreateCustomer(ctx, dbmodels.CreateCustomerParams{
		CustomerID: toPGUUID(customer.ID()),
		Name:       customer.Name(),
		Phone:      customer.Phone(),
		Email:      customer.Email(),
		CreatedAt:  customer.CreatedAt(),
		UpdatedAt:  customer.UpdatedAt(),
	})
	if common.IsUniqueViolationError(err, "customers_phone_key") {
		return domain.Customer{}, app.ErrCustomerPhoneTaken
	}
	if common.IsUniqueViolationError(err, "customers_email_unique_when_present") {
		return domain.Customer{}, app.ErrCustomerEmailTaken
	}
	if err != nil {
		return domain.Customer{}, err
	}
	return customerFromRow(row), nil
}

func (r *DealershipRepository) GetCustomer(ctx context.Context, customerID uuid.UUID) (domain.Customer, error) {
	row, err := r.queries.GetCustomerByID(ctx, toPGUUID(customerID))
	return customerFromQuery(row, err)
}

func (r *DealershipRepository) UpdateCustomer(ctx context.Context, customer domain.Customer) (domain.Customer, error) {
	row, err := r.queries.UpdateCustomer(ctx, dbmodels.UpdateCustomerParams{
		CustomerID: toPGUUID(customer.ID()),
		Name:       customer.Name(),
		Phone:      customer.Phone(),
		Email:      customer.Email(),
		UpdatedAt:  customer.UpdatedAt(),
	})
	if common.IsUniqueViolationError(err, "customers_phone_key") {
		return domain.Customer{}, app.ErrCustomerPhoneTaken
	}
	if common.IsUniqueViolationError(err, "customers_email_unique_when_present") {
		return domain.Customer{}, app.ErrCustomerEmailTaken
	}
	return customerFromQuery(row, err)
}

func (r *DealershipRepository) GetCustomerByPhone(ctx context.Context, phone string) (domain.Customer, error) {
	row, err := r.queries.GetCustomerByPhone(ctx, phone)
	return customerFromQuery(row, err)
}

func (r *DealershipRepository) GetCustomerByEmail(ctx context.Context, email string) (domain.Customer, error) {
	row, err := r.queries.GetCustomerByEmail(ctx, &email)
	return customerFromQuery(row, err)
}

func customerFromQuery(row dbmodels.AppointmentSchedulerCustomer, err error) (domain.Customer, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Customer{}, app.ErrCustomerNotFound
	}
	if err != nil {
		return domain.Customer{}, err
	}
	return customerFromRow(row), nil
}

func customerFromRow(row dbmodels.AppointmentSchedulerCustomer) domain.Customer {
	return domain.RestoreCustomer(
		fromPGUUID(row.CustomerID),
		row.Name,
		row.Phone,
		row.Email,
		row.CreatedAt,
		row.UpdatedAt,
	)
}

func (r *DealershipRepository) GetActiveVehicleManagerDealership(ctx context.Context, authUserID uuid.UUID) (uuid.UUID, error) {
	dealershipID, err := r.queries.GetActiveVehicleManagerDealership(ctx, toPGUUID(authUserID))
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, app.ErrVehicleCustomerForbidden
	}
	if err != nil {
		return uuid.Nil, err
	}
	return fromPGUUID(dealershipID), nil
}

func (r *DealershipRepository) CreateVehicle(ctx context.Context, dealershipID uuid.UUID, vehicle domain.Vehicle) error {
	err := common.UpdateInTx(ctx, r.database, func(ctx context.Context, tx pgx.Tx) error {
		queries := r.queries.WithTx(tx)
		if _, err := queries.GetCustomerByID(ctx, toPGUUID(vehicle.CustomerID())); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return app.ErrCustomerNotFound
			}
			return err
		}
		if err := queries.ClaimCustomerDealership(ctx, dbmodels.ClaimCustomerDealershipParams{CustomerID: toPGUUID(vehicle.CustomerID()), DealershipID: toPGUUID(dealershipID)}); err != nil {
			return err
		}
		ownerDealershipID, err := queries.GetCustomerDealership(ctx, toPGUUID(vehicle.CustomerID()))
		if err != nil {
			return err
		}
		if fromPGUUID(ownerDealershipID) != dealershipID {
			return app.ErrVehicleCustomerForbidden
		}
		return queries.CreateVehicle(ctx, dbmodels.CreateVehicleParams{
			VehicleID:         toPGUUID(vehicle.ID()),
			CustomerID:        toPGUUID(vehicle.CustomerID()),
			Vin:               vehicle.VIN(),
			RegistrationPlate: vehicle.RegistrationPlate(),
			Make:              vehicle.Make(),
			Model:             vehicle.Model(),
			ModelYear:         toPGInt16(vehicle.ModelYear()),
			CreatedAt:         vehicle.CreatedAt(),
			UpdatedAt:         vehicle.UpdatedAt(),
		})
	})
	if common.IsUniqueViolationError(err, "vehicles_vin_unique_when_present") {
		return app.ErrVehicleVINTaken
	}
	return err
}

func (r *DealershipRepository) GetVehicle(ctx context.Context, vehicleID uuid.UUID) (domain.Vehicle, error) {
	row, err := r.queries.GetVehicle(ctx, toPGUUID(vehicleID))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Vehicle{}, app.ErrVehicleNotFound
	}
	if err != nil {
		return domain.Vehicle{}, err
	}
	return vehicleFromRow(row.VehicleID, row.CustomerID, row.Vin, row.RegistrationPlate, row.Make, row.Model, row.ModelYear, row.CreatedAt, row.UpdatedAt), nil
}

func (r *DealershipRepository) ListCustomerVehicles(ctx context.Context, customerID uuid.UUID) ([]domain.Vehicle, error) {
	rows, err := r.queries.ListCustomerVehicles(ctx, toPGUUID(customerID))
	if err != nil {
		return nil, err
	}
	vehicles := make([]domain.Vehicle, 0, len(rows))
	for _, row := range rows {
		vehicles = append(vehicles, vehicleFromRow(row.VehicleID, row.CustomerID, row.Vin, row.RegistrationPlate, row.Make, row.Model, row.ModelYear, row.CreatedAt, row.UpdatedAt))
	}
	return vehicles, nil
}

func (r *DealershipRepository) CustomerBelongsToDealership(ctx context.Context, customerID, dealershipID uuid.UUID) (bool, error) {
	ownerDealershipID, err := r.queries.GetCustomerDealership(ctx, toPGUUID(customerID))
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return fromPGUUID(ownerDealershipID) == dealershipID, nil
}

func (r *DealershipRepository) UpdateVehicle(ctx context.Context, vehicle domain.Vehicle) error {
	rows, err := r.queries.UpdateVehicle(ctx, dbmodels.UpdateVehicleParams{
		Vin:               vehicle.VIN(),
		RegistrationPlate: vehicle.RegistrationPlate(),
		Make:              vehicle.Make(),
		Model:             vehicle.Model(),
		ModelYear:         toPGInt16(vehicle.ModelYear()),
		UpdatedAt:         vehicle.UpdatedAt(),
		VehicleID:         toPGUUID(vehicle.ID()),
	})
	if common.IsUniqueViolationError(err, "vehicles_vin_unique_when_present") {
		return app.ErrVehicleVINTaken
	}
	if err != nil {
		return err
	}
	if rows == 0 {
		return app.ErrVehicleNotFound
	}
	return nil
}

func (r *DealershipRepository) DeleteVehicle(ctx context.Context, vehicleID uuid.UUID, deletedAt time.Time) error {
	rows, err := r.queries.DeleteVehicle(ctx, dbmodels.DeleteVehicleParams{VehicleID: toPGUUID(vehicleID), DeletedAt: deletedAt})
	if err != nil {
		return err
	}
	if rows == 0 {
		return app.ErrVehicleNotFound
	}
	return nil
}

func vehicleFromRow(vehicleID, customerID pgtype.UUID, vin, registrationPlate *string, make, model string, modelYear *int16, createdAt, updatedAt time.Time) domain.Vehicle {
	return domain.RestoreVehicle(fromPGUUID(vehicleID), fromPGUUID(customerID), vin, registrationPlate, make, model, fromPGInt16(modelYear), createdAt, updatedAt)
}

// CreateDealershipUser creates a scheduler user and exactly one role in one transaction.
func (r *DealershipRepository) CreateDealershipUser(ctx context.Context, user domain.DealershipUser) error {
	err := common.UpdateInTx(ctx, r.database, func(ctx context.Context, tx pgx.Tx) error {
		queries := r.queries.WithTx(tx)
		if _, err := queries.GetActiveDealership(ctx, toPGUUID(user.DealershipID())); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return app.ErrDealershipNotFound
			}
			return err
		}
		if _, err := queries.GetSchedulerUserByAuthUserID(ctx, toPGUUID(user.AuthUserID())); err == nil {
			return app.ErrAuthUserAlreadyAssigned
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		role, err := queries.GetRoleByCode(ctx, user.Role())
		if err != nil {
			return err
		}
		_, err = queries.CreateSchedulerUser(ctx, dbmodels.CreateSchedulerUserParams{
			UserID:       toPGUUID(user.ID()),
			AuthUserID:   toPGUUID(user.AuthUserID()),
			Name:         user.Name(),
			Email:        stringPointer(user.Email()),
			DealershipID: toPGUUID(user.DealershipID()),
			CreatedAt:    user.CreatedAt(),
			UpdatedAt:    user.UpdatedAt(),
			UserRoleID:   toPGUUID(uuid.New()),
			RoleID:       role.RoleID,
		})
		return err
	})
	if common.IsUniqueViolationError(err, "users_auth_user_id_unique_when_present") {
		return app.ErrAuthUserAlreadyAssigned
	}
	return err
}

func stringPointer(value string) *string { return &value }

// CreateDealershipAdmin validates scheduler-side references and creates the
// user plus its only role in one database transaction.
func (r *DealershipRepository) CreateDealershipAdmin(ctx context.Context, admin domain.DealershipAdmin) error {
	err := common.UpdateInTx(ctx, r.database, func(ctx context.Context, tx pgx.Tx) error {
		queries := r.queries.WithTx(tx)
		if _, err := queries.GetActiveDealership(ctx, toPGUUID(admin.DealershipID())); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return app.ErrDealershipNotFound
			}
			return err
		}
		if _, err := queries.GetSchedulerUserByAuthUserID(ctx, toPGUUID(admin.AuthUserID())); err == nil {
			return app.ErrAuthUserAlreadyAssigned
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		role, err := queries.GetRoleByCode(ctx, "admin")
		if err != nil {
			return err
		}
		_, err = queries.CreateSchedulerAdmin(ctx, dbmodels.CreateSchedulerAdminParams{
			UserID:       toPGUUID(admin.ID()),
			AuthUserID:   toPGUUID(admin.AuthUserID()),
			Name:         admin.Name(),
			Phone:        admin.Phone(),
			Email:        admin.Email(),
			DealershipID: toPGUUID(admin.DealershipID()),
			CreatedAt:    admin.CreatedAt(),
			UpdatedAt:    admin.UpdatedAt(),
			UserRoleID:   toPGUUID(uuid.New()),
			RoleID:       role.RoleID,
		})
		return err
	})
	if common.IsUniqueViolationError(err, "users_auth_user_id_unique_when_present") {
		return app.ErrAuthUserAlreadyAssigned
	}
	return err
}

func (r *DealershipRepository) CreateServiceType(ctx context.Context, serviceType domain.ServiceType) error {
	err := r.queries.CreateServiceTypes(ctx, dbmodels.CreateServiceTypesParams{
		ServiceTypeID:          toPGUUID(serviceType.ID()),
		DealershipID:           toPGUUID(serviceType.DealershipID()),
		Name:                   serviceType.Name(),
		DefaultDurationMinutes: int32(serviceType.DefaultDurationMinutes()),
		MinDurationMinutes:     int32(serviceType.MinDurationMinutes()),
		MaxDurationMinutes:     int32(serviceType.MaxDurationMinutes()),
		IsActive:               serviceType.IsActive(),
		CreatedAt:              serviceType.CreatedAt(),
		UpdatedAt:              serviceType.UpdatedAt(),
	})
	if common.IsUniqueViolationError(err, "service_types_dealership_name_unique") {
		return app.ErrServiceTypeNameTaken
	}
	return err
}

func (r *DealershipRepository) GetServiceType(ctx context.Context, dealershipID, serviceTypeID uuid.UUID) (domain.ServiceType, error) {
	row, err := r.queries.GetServiceType(ctx, dbmodels.GetServiceTypeParams{
		ServiceTypeID: toPGUUID(serviceTypeID),
		DealershipID:  toPGUUID(dealershipID),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ServiceType{}, app.ErrServiceTypeNotFound
	}
	if err != nil {
		return domain.ServiceType{}, err
	}
	return serviceTypeFromRow(row.ServiceTypeID, row.DealershipID, row.Name, row.DefaultDurationMinutes, row.MinDurationMinutes, row.MaxDurationMinutes, row.IsActive, row.CreatedAt, row.UpdatedAt)
}

func (r *DealershipRepository) ListServiceTypes(ctx context.Context, dealershipID uuid.UUID) ([]domain.ServiceType, error) {
	rows, err := r.queries.ListServiceTypes(ctx, toPGUUID(dealershipID))
	if err != nil {
		return nil, err
	}
	serviceTypes := make([]domain.ServiceType, 0, len(rows))
	for _, row := range rows {
		serviceType, err := serviceTypeFromRow(row.ServiceTypeID, row.DealershipID, row.Name, row.DefaultDurationMinutes, row.MinDurationMinutes, row.MaxDurationMinutes, row.IsActive, row.CreatedAt, row.UpdatedAt)
		if err != nil {
			return nil, err
		}
		serviceTypes = append(serviceTypes, serviceType)
	}
	return serviceTypes, nil
}

func (r *DealershipRepository) UpdateServiceType(ctx context.Context, serviceType domain.ServiceType) error {
	updated, err := r.queries.UpdateServiceTypes(ctx, dbmodels.UpdateServiceTypesParams{
		Name:                   serviceType.Name(),
		DefaultDurationMinutes: int32(serviceType.DefaultDurationMinutes()),
		MinDurationMinutes:     int32(serviceType.MinDurationMinutes()),
		MaxDurationMinutes:     int32(serviceType.MaxDurationMinutes()),
		IsActive:               serviceType.IsActive(),
		UpdatedAt:              serviceType.UpdatedAt(),
		ServiceTypeID:          toPGUUID(serviceType.ID()),
		DealershipID:           toPGUUID(serviceType.DealershipID()),
	})
	if common.IsUniqueViolationError(err, "service_types_dealership_name_unique") {
		return app.ErrServiceTypeNameTaken
	}
	if err != nil {
		return err
	}
	if updated == 0 {
		return app.ErrServiceTypeNotFound
	}
	return nil
}

func (r *DealershipRepository) DeleteServiceType(ctx context.Context, dealershipID, serviceTypeID uuid.UUID, deletedAt time.Time) error {
	return common.UpdateInTx(ctx, r.database, func(ctx context.Context, tx pgx.Tx) error {
		queries := r.queries.WithTx(tx)
		_, err := queries.GetServiceType(ctx, dbmodels.GetServiceTypeParams{
			ServiceTypeID: toPGUUID(serviceTypeID),
			DealershipID:  toPGUUID(dealershipID),
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return app.ErrServiceTypeNotFound
		}
		if err != nil {
			return err
		}
		inUse, err := queries.HasAppointmentsForServiceType(ctx, toPGUUID(serviceTypeID))
		if err != nil {
			return err
		}
		if inUse {
			return app.ErrServiceTypeInUse
		}
		deleted, err := queries.DeleteServiceTypes(ctx, dbmodels.DeleteServiceTypesParams{
			DeletedAt:     deletedAt,
			ServiceTypeID: toPGUUID(serviceTypeID),
			DealershipID:  toPGUUID(dealershipID),
		})
		if err != nil {
			return err
		}
		if deleted == 0 {
			return app.ErrServiceTypeNotFound
		}
		return nil
	})
}

func (r *DealershipRepository) CreateServiceTypeRequiredSkill(ctx context.Context, dealershipID uuid.UUID, requiredSkill domain.ServiceTypeRequiredSkill) (domain.ServiceTypeRequiredSkill, error) {
	_, err := r.queries.CreateServiceTypeRequiredSkill(ctx, dbmodels.CreateServiceTypeRequiredSkillParams{
		ServiceTypeRequiredSkillID: toPGUUID(requiredSkill.ID()),
		CreatedAt:                  requiredSkill.CreatedAt(), UpdatedAt: requiredSkill.UpdatedAt(),
		SkillID: toPGUUID(requiredSkill.SkillID()), ServiceTypeID: toPGUUID(requiredSkill.ServiceTypeID()), DealershipID: toPGUUID(dealershipID),
	})
	if common.IsUniqueViolationError(err, "service_type_required_skills_service_type_skill_unique") {
		return domain.ServiceTypeRequiredSkill{}, app.ErrServiceTypeRequiredSkillTaken
	}
	if errors.Is(err, pgx.ErrNoRows) {
		if _, serviceTypeErr := r.GetServiceType(ctx, dealershipID, requiredSkill.ServiceTypeID()); serviceTypeErr != nil {
			return domain.ServiceTypeRequiredSkill{}, serviceTypeErr
		}
		return domain.ServiceTypeRequiredSkill{}, app.ErrSkillNotFound
	}
	if err != nil {
		return domain.ServiceTypeRequiredSkill{}, err
	}
	return r.GetServiceTypeRequiredSkill(ctx, dealershipID, requiredSkill.ServiceTypeID(), requiredSkill.ID())
}

func (r *DealershipRepository) GetServiceTypeRequiredSkill(ctx context.Context, dealershipID, serviceTypeID, requiredSkillID uuid.UUID) (domain.ServiceTypeRequiredSkill, error) {
	row, err := r.queries.GetServiceTypeRequiredSkill(ctx, dbmodels.GetServiceTypeRequiredSkillParams{ServiceTypeRequiredSkillID: toPGUUID(requiredSkillID), ServiceTypeID: toPGUUID(serviceTypeID), DealershipID: toPGUUID(dealershipID)})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ServiceTypeRequiredSkill{}, app.ErrServiceTypeRequiredSkillNotFound
	}
	if err != nil {
		return domain.ServiceTypeRequiredSkill{}, err
	}
	return requiredSkillFromRow(row.ServiceTypeRequiredSkillID, row.ServiceTypeID, row.SkillID, row.Code, row.Name, row.CreatedAt, row.UpdatedAt)
}

func (r *DealershipRepository) ListServiceTypeRequiredSkills(ctx context.Context, dealershipID, serviceTypeID uuid.UUID) ([]domain.ServiceTypeRequiredSkill, error) {
	if _, err := r.GetServiceType(ctx, dealershipID, serviceTypeID); err != nil {
		return nil, err
	}
	rows, err := r.queries.ListServiceTypeRequiredSkills(ctx, dbmodels.ListServiceTypeRequiredSkillsParams{ServiceTypeID: toPGUUID(serviceTypeID), DealershipID: toPGUUID(dealershipID)})
	if err != nil {
		return nil, err
	}
	result := make([]domain.ServiceTypeRequiredSkill, 0, len(rows))
	for _, row := range rows {
		requiredSkill, err := requiredSkillFromRow(row.ServiceTypeRequiredSkillID, row.ServiceTypeID, row.SkillID, row.Code, row.Name, row.CreatedAt, row.UpdatedAt)
		if err != nil {
			return nil, err
		}
		result = append(result, requiredSkill)
	}
	return result, nil
}

func (r *DealershipRepository) UpdateServiceTypeRequiredSkill(ctx context.Context, dealershipID uuid.UUID, requiredSkill domain.ServiceTypeRequiredSkill) (domain.ServiceTypeRequiredSkill, error) {
	skillExists, err := r.queries.SkillExists(ctx, toPGUUID(requiredSkill.SkillID()))
	if err != nil {
		return domain.ServiceTypeRequiredSkill{}, err
	}
	if !skillExists {
		return domain.ServiceTypeRequiredSkill{}, app.ErrSkillNotFound
	}
	_, err = r.queries.UpdateServiceTypeRequiredSkill(ctx, dbmodels.UpdateServiceTypeRequiredSkillParams{SkillID: toPGUUID(requiredSkill.SkillID()), UpdatedAt: requiredSkill.UpdatedAt(), ServiceTypeRequiredSkillID: toPGUUID(requiredSkill.ID()), ServiceTypeID: toPGUUID(requiredSkill.ServiceTypeID()), DealershipID: toPGUUID(dealershipID)})
	if common.IsUniqueViolationError(err, "service_type_required_skills_service_type_skill_unique") {
		return domain.ServiceTypeRequiredSkill{}, app.ErrServiceTypeRequiredSkillTaken
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ServiceTypeRequiredSkill{}, app.ErrServiceTypeRequiredSkillNotFound
	}
	if err != nil {
		return domain.ServiceTypeRequiredSkill{}, err
	}
	return r.GetServiceTypeRequiredSkill(ctx, dealershipID, requiredSkill.ServiceTypeID(), requiredSkill.ID())
}

func (r *DealershipRepository) DeleteServiceTypeRequiredSkill(ctx context.Context, dealershipID, serviceTypeID, requiredSkillID uuid.UUID) error {
	deleted, err := r.queries.DeleteServiceTypeRequiredSkill(ctx, dbmodels.DeleteServiceTypeRequiredSkillParams{ServiceTypeRequiredSkillID: toPGUUID(requiredSkillID), ServiceTypeID: toPGUUID(serviceTypeID), DealershipID: toPGUUID(dealershipID)})
	if err != nil {
		return err
	}
	if deleted == 0 {
		return app.ErrServiceTypeRequiredSkillNotFound
	}
	return nil
}

func (r *DealershipRepository) CreateServiceTypeRequiredBayCapability(ctx context.Context, dealershipID uuid.UUID, requiredCapability domain.ServiceTypeRequiredBayCapability) (domain.ServiceTypeRequiredBayCapability, error) {
	_, err := r.queries.CreateServiceTypeRequiredBayCapability(ctx, dbmodels.CreateServiceTypeRequiredBayCapabilityParams{
		ServiceTypeRequiredBayCapabilityID: toPGUUID(requiredCapability.ID()),
		ServiceTypeID:                      toPGUUID(requiredCapability.ServiceTypeID()),
		BayCapabilityID:                    toPGUUID(requiredCapability.BayCapabilityID()),
		DealershipID:                       toPGUUID(dealershipID),
		CreatedAt:                          requiredCapability.CreatedAt(),
		UpdatedAt:                          requiredCapability.UpdatedAt(),
	})
	if common.IsUniqueViolationError(err, "service_type_required_bay_capabilities_service_type_bay_capability_unique") {
		return domain.ServiceTypeRequiredBayCapability{}, app.ErrServiceTypeRequiredBayCapabilityTaken
	}
	if errors.Is(err, pgx.ErrNoRows) {
		if _, serviceTypeErr := r.GetServiceType(ctx, dealershipID, requiredCapability.ServiceTypeID()); serviceTypeErr != nil {
			return domain.ServiceTypeRequiredBayCapability{}, serviceTypeErr
		}
		return domain.ServiceTypeRequiredBayCapability{}, app.ErrBayCapabilityNotFound
	}
	if err != nil {
		return domain.ServiceTypeRequiredBayCapability{}, err
	}
	return r.GetServiceTypeRequiredBayCapability(ctx, dealershipID, requiredCapability.ServiceTypeID(), requiredCapability.ID())
}

func (r *DealershipRepository) GetServiceTypeRequiredBayCapability(ctx context.Context, dealershipID, serviceTypeID, requiredCapabilityID uuid.UUID) (domain.ServiceTypeRequiredBayCapability, error) {
	row, err := r.queries.GetServiceTypeRequiredBayCapability(ctx, dbmodels.GetServiceTypeRequiredBayCapabilityParams{
		ServiceTypeRequiredBayCapabilityID: toPGUUID(requiredCapabilityID),
		ServiceTypeID:                      toPGUUID(serviceTypeID),
		DealershipID:                       toPGUUID(dealershipID),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ServiceTypeRequiredBayCapability{}, app.ErrServiceTypeRequiredBayCapabilityNotFound
	}
	if err != nil {
		return domain.ServiceTypeRequiredBayCapability{}, err
	}
	return requiredBayCapabilityFromRow(row.ServiceTypeRequiredBayCapabilityID, row.ServiceTypeID, row.BayCapabilityID, row.Code, row.Name, row.CreatedAt, row.UpdatedAt)
}

func (r *DealershipRepository) ListServiceTypeRequiredBayCapabilities(ctx context.Context, dealershipID, serviceTypeID uuid.UUID) ([]domain.ServiceTypeRequiredBayCapability, error) {
	if _, err := r.GetServiceType(ctx, dealershipID, serviceTypeID); err != nil {
		return nil, err
	}
	rows, err := r.queries.ListServiceTypeRequiredBayCapabilities(ctx, dbmodels.ListServiceTypeRequiredBayCapabilitiesParams{ServiceTypeID: toPGUUID(serviceTypeID), DealershipID: toPGUUID(dealershipID)})
	if err != nil {
		return nil, err
	}
	result := make([]domain.ServiceTypeRequiredBayCapability, 0, len(rows))
	for _, row := range rows {
		requiredCapability, err := requiredBayCapabilityFromRow(row.ServiceTypeRequiredBayCapabilityID, row.ServiceTypeID, row.BayCapabilityID, row.Code, row.Name, row.CreatedAt, row.UpdatedAt)
		if err != nil {
			return nil, err
		}
		result = append(result, requiredCapability)
	}
	return result, nil
}

func (r *DealershipRepository) UpdateServiceTypeRequiredBayCapability(ctx context.Context, dealershipID uuid.UUID, requiredCapability domain.ServiceTypeRequiredBayCapability) (domain.ServiceTypeRequiredBayCapability, error) {
	exists, err := r.queries.BayCapabilityExists(ctx, toPGUUID(requiredCapability.BayCapabilityID()))
	if err != nil {
		return domain.ServiceTypeRequiredBayCapability{}, err
	}
	if !exists {
		return domain.ServiceTypeRequiredBayCapability{}, app.ErrBayCapabilityNotFound
	}
	_, err = r.queries.UpdateServiceTypeRequiredBayCapability(ctx, dbmodels.UpdateServiceTypeRequiredBayCapabilityParams{
		BayCapabilityID:                    toPGUUID(requiredCapability.BayCapabilityID()),
		UpdatedAt:                          requiredCapability.UpdatedAt(),
		ServiceTypeRequiredBayCapabilityID: toPGUUID(requiredCapability.ID()),
		ServiceTypeID:                      toPGUUID(requiredCapability.ServiceTypeID()),
		DealershipID:                       toPGUUID(dealershipID),
	})
	if common.IsUniqueViolationError(err, "service_type_required_bay_capabilities_service_type_bay_capability_unique") {
		return domain.ServiceTypeRequiredBayCapability{}, app.ErrServiceTypeRequiredBayCapabilityTaken
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ServiceTypeRequiredBayCapability{}, app.ErrServiceTypeRequiredBayCapabilityNotFound
	}
	if err != nil {
		return domain.ServiceTypeRequiredBayCapability{}, err
	}
	return r.GetServiceTypeRequiredBayCapability(ctx, dealershipID, requiredCapability.ServiceTypeID(), requiredCapability.ID())
}

func (r *DealershipRepository) DeleteServiceTypeRequiredBayCapability(ctx context.Context, dealershipID, serviceTypeID, requiredCapabilityID uuid.UUID) error {
	deleted, err := r.queries.DeleteServiceTypeRequiredBayCapability(ctx, dbmodels.DeleteServiceTypeRequiredBayCapabilityParams{
		ServiceTypeRequiredBayCapabilityID: toPGUUID(requiredCapabilityID),
		ServiceTypeID:                      toPGUUID(serviceTypeID),
		DealershipID:                       toPGUUID(dealershipID),
	})
	if err != nil {
		return err
	}
	if deleted == 0 {
		return app.ErrServiceTypeRequiredBayCapabilityNotFound
	}
	return nil
}

func (r *DealershipRepository) CreateServiceBayCapability(ctx context.Context, dealershipID uuid.UUID, capability domain.ServiceBayCapability) (domain.ServiceBayCapability, error) {
	row, err := r.queries.CreateServiceBayCapability(ctx, dbmodels.CreateServiceBayCapabilityParams{
		ServiceBayCapabilityID: toPGUUID(capability.ID()),
		ServiceBayID:           toPGUUID(capability.ServiceBayID()),
		BayCapabilityID:        toPGUUID(capability.BayCapabilityID()),
		DealershipID:           toPGUUID(dealershipID),
		CreatedAt:              capability.CreatedAt(),
		UpdatedAt:              capability.UpdatedAt(),
	})
	if common.IsUniqueViolationError(err, "service_bay_capabilities_service_bay_bay_capability_unique") {
		return domain.ServiceBayCapability{}, app.ErrServiceBayCapabilityTaken
	}
	if errors.Is(err, pgx.ErrNoRows) {
		if _, serviceBayErr := r.GetServiceBay(ctx, dealershipID, capability.ServiceBayID()); serviceBayErr != nil {
			return domain.ServiceBayCapability{}, serviceBayErr
		}
		return domain.ServiceBayCapability{}, app.ErrBayCapabilityNotFound
	}
	if err != nil {
		return domain.ServiceBayCapability{}, err
	}
	return r.GetServiceBayCapability(ctx, dealershipID, uuid.UUID(row.ServiceBayID.Bytes), uuid.UUID(row.ServiceBayCapabilityID.Bytes))
}

func (r *DealershipRepository) GetServiceBayCapability(ctx context.Context, dealershipID, serviceBayID, serviceBayCapabilityID uuid.UUID) (domain.ServiceBayCapability, error) {
	row, err := r.queries.GetServiceBayCapability(ctx, dbmodels.GetServiceBayCapabilityParams{
		ServiceBayCapabilityID: toPGUUID(serviceBayCapabilityID),
		ServiceBayID:           toPGUUID(serviceBayID),
		DealershipID:           toPGUUID(dealershipID),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ServiceBayCapability{}, app.ErrServiceBayCapabilityNotFound
	}
	if err != nil {
		return domain.ServiceBayCapability{}, err
	}
	return serviceBayCapabilityFromRow(row.ServiceBayCapabilityID, row.ServiceBayID, row.BayCapabilityID, row.Code, row.Name, row.CreatedAt, row.UpdatedAt)
}

func (r *DealershipRepository) ListServiceBayCapabilities(ctx context.Context, dealershipID, serviceBayID uuid.UUID) ([]domain.ServiceBayCapability, error) {
	if _, err := r.GetServiceBay(ctx, dealershipID, serviceBayID); err != nil {
		return nil, err
	}
	rows, err := r.queries.ListServiceBayCapabilities(ctx, dbmodels.ListServiceBayCapabilitiesParams{
		ServiceBayID: toPGUUID(serviceBayID),
		DealershipID: toPGUUID(dealershipID),
	})
	if err != nil {
		return nil, err
	}
	capabilities := make([]domain.ServiceBayCapability, 0, len(rows))
	for _, row := range rows {
		capability, err := serviceBayCapabilityFromRow(row.ServiceBayCapabilityID, row.ServiceBayID, row.BayCapabilityID, row.Code, row.Name, row.CreatedAt, row.UpdatedAt)
		if err != nil {
			return nil, err
		}
		capabilities = append(capabilities, capability)
	}
	return capabilities, nil
}

func (r *DealershipRepository) UpdateServiceBayCapability(ctx context.Context, dealershipID uuid.UUID, capability domain.ServiceBayCapability) (domain.ServiceBayCapability, error) {
	exists, err := r.queries.BayCapabilityExists(ctx, toPGUUID(capability.BayCapabilityID()))
	if err != nil {
		return domain.ServiceBayCapability{}, err
	}
	if !exists {
		return domain.ServiceBayCapability{}, app.ErrBayCapabilityNotFound
	}
	_, err = r.queries.UpdateServiceBayCapability(ctx, dbmodels.UpdateServiceBayCapabilityParams{
		BayCapabilityID:        toPGUUID(capability.BayCapabilityID()),
		UpdatedAt:              capability.UpdatedAt(),
		ServiceBayCapabilityID: toPGUUID(capability.ID()),
		ServiceBayID:           toPGUUID(capability.ServiceBayID()),
		DealershipID:           toPGUUID(dealershipID),
	})
	if common.IsUniqueViolationError(err, "service_bay_capabilities_service_bay_bay_capability_unique") {
		return domain.ServiceBayCapability{}, app.ErrServiceBayCapabilityTaken
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ServiceBayCapability{}, app.ErrServiceBayCapabilityNotFound
	}
	if err != nil {
		return domain.ServiceBayCapability{}, err
	}
	return r.GetServiceBayCapability(ctx, dealershipID, capability.ServiceBayID(), capability.ID())
}

func (r *DealershipRepository) DeleteServiceBayCapability(ctx context.Context, dealershipID, serviceBayID, serviceBayCapabilityID uuid.UUID) error {
	deleted, err := r.queries.DeleteServiceBayCapability(ctx, dbmodels.DeleteServiceBayCapabilityParams{
		ServiceBayCapabilityID: toPGUUID(serviceBayCapabilityID),
		ServiceBayID:           toPGUUID(serviceBayID),
		DealershipID:           toPGUUID(dealershipID),
	})
	if err != nil {
		return err
	}
	if deleted == 0 {
		return app.ErrServiceBayCapabilityNotFound
	}
	return nil
}

func (r *DealershipRepository) CreateServiceBay(ctx context.Context, serviceBay domain.ServiceBay) error {
	err := r.queries.CreateServiceBay(ctx, dbmodels.CreateServiceBayParams{
		ServiceBayID: toPGUUID(serviceBay.ID()),
		DealershipID: toPGUUID(serviceBay.DealershipID()),
		Code:         serviceBay.Code(),
		Name:         serviceBay.Name(),
		IsActive:     serviceBay.IsActive(),
		CreatedAt:    serviceBay.CreatedAt(),
		UpdatedAt:    serviceBay.UpdatedAt(),
	})
	if common.IsUniqueViolationError(err, "service_bays_dealership_code_lower_unique") {
		return app.ErrServiceBayCodeTaken
	}
	return err
}

func (r *DealershipRepository) GetServiceBay(ctx context.Context, dealershipID, serviceBayID uuid.UUID) (domain.ServiceBay, error) {
	row, err := r.queries.GetServiceBay(ctx, dbmodels.GetServiceBayParams{
		ServiceBayID: toPGUUID(serviceBayID),
		DealershipID: toPGUUID(dealershipID),
	})
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ServiceBay{}, app.ErrServiceBayNotFound
	}
	if err != nil {
		return domain.ServiceBay{}, err
	}
	return serviceBayFromRow(row.ServiceBayID, row.DealershipID, row.Code, row.Name, row.IsActive, row.CreatedAt, row.UpdatedAt)
}

func (r *DealershipRepository) ListServiceBays(ctx context.Context, dealershipID uuid.UUID, isActive *bool, limit, offset int) ([]domain.ServiceBay, error) {
	rows, err := r.queries.ListServiceBays(ctx, dbmodels.ListServiceBaysParams{
		DealershipID: toPGUUID(dealershipID),
		IsActive:     isActive,
		LimitCount:   int32(limit),
		OffsetCount:  int32(offset),
	})
	if err != nil {
		return nil, err
	}
	serviceBays := make([]domain.ServiceBay, 0, len(rows))
	for _, row := range rows {
		serviceBay, err := serviceBayFromRow(row.ServiceBayID, row.DealershipID, row.Code, row.Name, row.IsActive, row.CreatedAt, row.UpdatedAt)
		if err != nil {
			return nil, err
		}
		serviceBays = append(serviceBays, serviceBay)
	}
	return serviceBays, nil
}

func (r *DealershipRepository) UpdateServiceBay(ctx context.Context, serviceBay domain.ServiceBay) error {
	updated, err := r.queries.UpdateServiceBay(ctx, dbmodels.UpdateServiceBayParams{
		Code:         serviceBay.Code(),
		Name:         serviceBay.Name(),
		IsActive:     serviceBay.IsActive(),
		UpdatedAt:    serviceBay.UpdatedAt(),
		ServiceBayID: toPGUUID(serviceBay.ID()),
		DealershipID: toPGUUID(serviceBay.DealershipID()),
	})
	if common.IsUniqueViolationError(err, "service_bays_dealership_code_lower_unique") {
		return app.ErrServiceBayCodeTaken
	}
	if err != nil {
		return err
	}
	if updated == 0 {
		return app.ErrServiceBayNotFound
	}
	return nil
}

func (r *DealershipRepository) DeleteServiceBay(ctx context.Context, dealershipID, serviceBayID uuid.UUID, deletedAt time.Time) error {
	return common.UpdateInTx(ctx, r.database, func(ctx context.Context, tx pgx.Tx) error {
		queries := r.queries.WithTx(tx)
		_, err := queries.GetServiceBay(ctx, dbmodels.GetServiceBayParams{
			ServiceBayID: toPGUUID(serviceBayID),
			DealershipID: toPGUUID(dealershipID),
		})
		if errors.Is(err, pgx.ErrNoRows) {
			return app.ErrServiceBayNotFound
		}
		if err != nil {
			return err
		}
		inUse, err := queries.HasAppointmentsForServiceBay(ctx, toPGUUID(serviceBayID))
		if err != nil {
			return err
		}
		if inUse {
			return app.ErrServiceBayInUse
		}
		deleted, err := queries.DeleteServiceBay(ctx, dbmodels.DeleteServiceBayParams{
			DeletedAt:    deletedAt,
			ServiceBayID: toPGUUID(serviceBayID),
			DealershipID: toPGUUID(dealershipID),
		})
		if err != nil {
			return err
		}
		if deleted == 0 {
			return app.ErrServiceBayNotFound
		}
		return nil
	})
}

func serviceTypeFromRow(
	id, dealershipID pgtype.UUID,
	name string,
	defaultDurationMinutes, minDurationMinutes, maxDurationMinutes int32,
	isActive bool,
	createdAt, updatedAt time.Time,
) (domain.ServiceType, error) {
	return domain.RehydrateServiceType(
		uuid.UUID(id.Bytes),
		uuid.UUID(dealershipID.Bytes),
		name,
		int(defaultDurationMinutes),
		int(minDurationMinutes),
		int(maxDurationMinutes),
		isActive,
		createdAt,
		updatedAt,
	)
}

func requiredSkillFromRow(id, serviceTypeID, skillID pgtype.UUID, skillCode, skillName string, createdAt, updatedAt time.Time) (domain.ServiceTypeRequiredSkill, error) {
	return domain.RehydrateServiceTypeRequiredSkill(uuid.UUID(id.Bytes), uuid.UUID(serviceTypeID.Bytes), uuid.UUID(skillID.Bytes), skillCode, skillName, createdAt, updatedAt)
}

func requiredBayCapabilityFromRow(id, serviceTypeID, bayCapabilityID pgtype.UUID, capabilityCode, capabilityName string, createdAt, updatedAt time.Time) (domain.ServiceTypeRequiredBayCapability, error) {
	return domain.RehydrateServiceTypeRequiredBayCapability(uuid.UUID(id.Bytes), uuid.UUID(serviceTypeID.Bytes), uuid.UUID(bayCapabilityID.Bytes), capabilityCode, capabilityName, createdAt, updatedAt)
}

func serviceBayCapabilityFromRow(id, serviceBayID, bayCapabilityID pgtype.UUID, capabilityCode, capabilityName string, createdAt, updatedAt time.Time) (domain.ServiceBayCapability, error) {
	return domain.RehydrateServiceBayCapability(uuid.UUID(id.Bytes), uuid.UUID(serviceBayID.Bytes), uuid.UUID(bayCapabilityID.Bytes), capabilityCode, capabilityName, createdAt, updatedAt)
}

func serviceBayFromRow(id, dealershipID pgtype.UUID, code, name string, isActive bool, createdAt, updatedAt time.Time) (domain.ServiceBay, error) {
	return domain.RehydrateServiceBay(uuid.UUID(id.Bytes), uuid.UUID(dealershipID.Bytes), code, name, isActive, createdAt, updatedAt)
}

func toPGUUID(value uuid.UUID) pgtype.UUID {
	result := pgtype.UUID{Valid: true}
	copy(result.Bytes[:], value[:])
	return result
}

func fromPGUUID(value pgtype.UUID) uuid.UUID {
	if !value.Valid {
		return uuid.Nil
	}
	return uuid.UUID(value.Bytes)
}

func nullablePGUUID(value *uuid.UUID) pgtype.UUID {
	if value == nil {
		return pgtype.UUID{}
	}
	return toPGUUID(*value)
}

func toPGInt16(value *int) *int16 {
	if value == nil {
		return nil
	}
	converted := int16(*value)
	return &converted
}

func fromPGInt16(value *int16) *int {
	if value == nil {
		return nil
	}
	converted := int(*value)
	return &converted
}

func toPGTime(value time.Duration) pgtype.Time {
	return pgtype.Time{Microseconds: value.Microseconds(), Valid: true}
}

func operationTimeFromRow(row dbmodels.AppointmentSchedulerDealershipOperationTime) (domain.DealershipOperationTime, error) {
	return domain.RehydrateDealershipOperationTime(fromPGUUID(row.DealershipOperationTimeID), fromPGUUID(row.DealershipID), int(row.DayOfWeek), time.Duration(row.OpensAt.Microseconds)*time.Microsecond, time.Duration(row.ClosesAt.Microseconds)*time.Microsecond, row.CreatedAt, row.UpdatedAt)
}

func operationTimeWriteError(err error) error {
	if common.IsUniqueViolationError(err, "dealership_operation_time_no_overlap") {
		return app.ErrDealershipOperationTimeOverlaps
	}
	var postgresErr *pgconn.PgError
	if errors.As(err, &postgresErr) && postgresErr.Code == "23P01" && postgresErr.ConstraintName == "dealership_operation_time_no_overlap" {
		return app.ErrDealershipOperationTimeOverlaps
	}
	return err
}

func isDuplicateDealershipCode(err error) bool {
	var postgresErr *pgconn.PgError
	return errors.As(err, &postgresErr) && postgresErr.Code == "23505"
}
