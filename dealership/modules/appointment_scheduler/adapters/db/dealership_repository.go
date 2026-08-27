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

func serviceBayFromRow(id, dealershipID pgtype.UUID, code, name string, isActive bool, createdAt, updatedAt time.Time) (domain.ServiceBay, error) {
	return domain.RehydrateServiceBay(uuid.UUID(id.Bytes), uuid.UUID(dealershipID.Bytes), code, name, isActive, createdAt, updatedAt)
}

func toPGUUID(value uuid.UUID) pgtype.UUID {
	result := pgtype.UUID{Valid: true}
	copy(result.Bytes[:], value[:])
	return result
}

func isDuplicateDealershipCode(err error) bool {
	var postgresErr *pgconn.PgError
	return errors.As(err, &postgresErr) && postgresErr.Code == "23505"
}
