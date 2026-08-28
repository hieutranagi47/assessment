// Package app coordinates dealership use cases and authorization.
package app

import (
	"context"
	"errors"
	"net/mail"
	"strings"
	"time"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/auth/api/module/client"
	"assessment/modules/common"

	"github.com/google/uuid"
)

var (
	ErrDealershipCodeTaken                      = errors.New("dealership code already exists")
	ErrAuthUserAlreadyAssigned                  = errors.New("auth user already assigned")
	ErrDealershipNotFound                       = errors.New("dealership not found")
	ErrServiceTypeNameTaken                     = errors.New("service type name already exists")
	ErrServiceTypeNotFound                      = errors.New("service type not found")
	ErrServiceTypeInUse                         = errors.New("service type is referenced by an appointment")
	ErrServiceBayCodeTaken                      = errors.New("service bay code already exists")
	ErrServiceBayNotFound                       = errors.New("service bay not found")
	ErrServiceBayInUse                          = errors.New("service bay is referenced by an appointment")
	ErrServiceTypeRequiredSkillNotFound         = errors.New("service type required skill not found")
	ErrServiceTypeRequiredSkillTaken            = errors.New("service type already requires this skill")
	ErrSkillNotFound                            = errors.New("skill not found")
	ErrServiceTypeRequiredBayCapabilityNotFound = errors.New("service type required bay capability not found")
	ErrServiceTypeRequiredBayCapabilityTaken    = errors.New("service type already requires this bay capability")
	ErrBayCapabilityNotFound                    = errors.New("bay capability not found")
	ErrServiceBayCapabilityNotFound             = errors.New("service bay capability not found")
	ErrServiceBayCapabilityTaken                = errors.New("service bay already has this capability")
	ErrCustomerNotFound                         = errors.New("customer not found")
	ErrCustomerPhoneTaken                       = errors.New("customer phone already exists")
	ErrCustomerEmailTaken                       = errors.New("customer email already exists")
	ErrVehicleNotFound                          = errors.New("vehicle not found")
	ErrVehicleVINTaken                          = errors.New("vehicle VIN already exists")
	ErrVehicleCustomerForbidden                 = errors.New("vehicle customer belongs to another dealership")
	ErrDealershipOperationTimeNotFound          = errors.New("dealership operation time not found")
	ErrDealershipOperationTimeOverlaps          = errors.New("dealership operation time overlaps an existing interval")
)

// Repository is the persistence capability the create-dealership use case needs.
type Repository interface {
	Create(context.Context, domain.Dealership) error
}

// AdminRepository owns the transaction that creates the scheduler user and
// grants its admin role. It has no auth persistence dependency.
type AdminRepository interface {
	CreateDealershipAdmin(context.Context, domain.DealershipAdmin) error
}

// DealershipUserRepository owns the transaction that creates a scheduler
// user and grants exactly one scheduler role.
type DealershipUserRepository interface {
	CreateDealershipUser(context.Context, domain.DealershipUser) error
}

// CustomerRepository holds the global-customer persistence and the existing
// scheduler employee role check used by every customer operation.
type CustomerRepository interface {
	IsActiveCustomerEmployee(context.Context, uuid.UUID) (bool, error)
	CreateCustomer(context.Context, domain.Customer) (domain.Customer, error)
	GetCustomer(context.Context, uuid.UUID) (domain.Customer, error)
	UpdateCustomer(context.Context, domain.Customer) (domain.Customer, error)
	GetCustomerByPhone(context.Context, string) (domain.Customer, error)
	GetCustomerByEmail(context.Context, string) (domain.Customer, error)
}

// VehicleRepository owns vehicle persistence and the dealership boundary for
// the global-customer model.
type VehicleRepository interface {
	GetActiveVehicleManagerDealership(context.Context, uuid.UUID) (uuid.UUID, error)
	CreateVehicle(context.Context, uuid.UUID, domain.Vehicle) error
	GetCustomer(context.Context, uuid.UUID) (domain.Customer, error)
	GetVehicle(context.Context, uuid.UUID) (domain.Vehicle, error)
	ListCustomerVehicles(context.Context, uuid.UUID) ([]domain.Vehicle, error)
	CustomerBelongsToDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	UpdateVehicle(context.Context, domain.Vehicle) error
	DeleteVehicle(context.Context, uuid.UUID, time.Time) error
}

// SchedulerAdminAuthorizer verifies scheduler-side admin access without
// coupling the application service to database tables or role records.
type SchedulerAdminAuthorizer interface {
	IsActiveSchedulerAdmin(context.Context, uuid.UUID) (bool, error)
}

type DealershipSchedulerAdminAuthorizer interface {
	IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error)
}

// ServiceTypeRepository contains only the persistence operations needed by
// straightforward dealership-scoped service type management.
type ServiceTypeRepository interface {
	IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	CreateServiceType(context.Context, domain.ServiceType) error
	GetServiceType(context.Context, uuid.UUID, uuid.UUID) (domain.ServiceType, error)
	ListServiceTypes(context.Context, uuid.UUID) ([]domain.ServiceType, error)
	UpdateServiceType(context.Context, domain.ServiceType) error
	DeleteServiceType(context.Context, uuid.UUID, uuid.UUID, time.Time) error
}

// ServiceBayRepository contains the dealership-scoped persistence operations
// needed to manage appointment workspaces.
type ServiceBayRepository interface {
	IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	CreateServiceBay(context.Context, domain.ServiceBay) error
	GetServiceBay(context.Context, uuid.UUID, uuid.UUID) (domain.ServiceBay, error)
	ListServiceBays(context.Context, uuid.UUID, *bool, int, int) ([]domain.ServiceBay, error)
	UpdateServiceBay(context.Context, domain.ServiceBay) error
	DeleteServiceBay(context.Context, uuid.UUID, uuid.UUID, time.Time) error
}

type DealershipOperationTimeRepository interface {
	IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	IsActiveDealership(context.Context, uuid.UUID) (bool, error)
	CreateDealershipOperationTime(context.Context, domain.DealershipOperationTime) error
	GetDealershipOperationTime(context.Context, uuid.UUID, uuid.UUID) (domain.DealershipOperationTime, error)
	ListDealershipOperationTimes(context.Context, uuid.UUID) ([]domain.DealershipOperationTime, error)
	UpdateDealershipOperationTime(context.Context, domain.DealershipOperationTime) error
	DeleteDealershipOperationTime(context.Context, uuid.UUID, uuid.UUID) error
}

// ServiceBayCapabilityRepository scopes every association through its owning
// service bay and dealership, preventing nested IDs from crossing boundaries.
type ServiceBayCapabilityRepository interface {
	IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	CreateServiceBayCapability(context.Context, uuid.UUID, domain.ServiceBayCapability) (domain.ServiceBayCapability, error)
	GetServiceBayCapability(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) (domain.ServiceBayCapability, error)
	ListServiceBayCapabilities(context.Context, uuid.UUID, uuid.UUID) ([]domain.ServiceBayCapability, error)
	UpdateServiceBayCapability(context.Context, uuid.UUID, domain.ServiceBayCapability) (domain.ServiceBayCapability, error)
	DeleteServiceBayCapability(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) error
}

// ServiceTypeRequiredSkillRepository keeps the association scoped through its
// owning service type, so nested resource IDs cannot cross dealership bounds.
type ServiceTypeRequiredSkillRepository interface {
	IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	CreateServiceTypeRequiredSkill(context.Context, uuid.UUID, domain.ServiceTypeRequiredSkill) (domain.ServiceTypeRequiredSkill, error)
	GetServiceTypeRequiredSkill(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) (domain.ServiceTypeRequiredSkill, error)
	ListServiceTypeRequiredSkills(context.Context, uuid.UUID, uuid.UUID) ([]domain.ServiceTypeRequiredSkill, error)
	UpdateServiceTypeRequiredSkill(context.Context, uuid.UUID, domain.ServiceTypeRequiredSkill) (domain.ServiceTypeRequiredSkill, error)
	DeleteServiceTypeRequiredSkill(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) error
}

type ServiceTypeRequiredBayCapabilityRepository interface {
	IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	CreateServiceTypeRequiredBayCapability(context.Context, uuid.UUID, domain.ServiceTypeRequiredBayCapability) (domain.ServiceTypeRequiredBayCapability, error)
	GetServiceTypeRequiredBayCapability(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) (domain.ServiceTypeRequiredBayCapability, error)
	ListServiceTypeRequiredBayCapabilities(context.Context, uuid.UUID, uuid.UUID) ([]domain.ServiceTypeRequiredBayCapability, error)
	UpdateServiceTypeRequiredBayCapability(context.Context, uuid.UUID, domain.ServiceTypeRequiredBayCapability) (domain.ServiceTypeRequiredBayCapability, error)
	DeleteServiceTypeRequiredBayCapability(context.Context, uuid.UUID, uuid.UUID, uuid.UUID) error
}

// UserInfoProvider is deliberately limited to auth's public module contract.
type UserInfoProvider interface {
	GetUserInfo(context.Context, uuid.UUID) (client.UserInfo, error)
	GetUserInfoByEmail(context.Context, string) (client.UserInfo, error)
}

type Service struct {
	repository Repository
	users      UserInfoProvider
	now        func() time.Time
	newID      func() uuid.UUID
}

func NewService(repository Repository, users UserInfoProvider) *Service {
	if repository == nil || users == nil {
		panic("dealership dependencies are required")
	}
	return &Service{repository: repository, users: users, now: time.Now, newID: uuid.New}
}

type CreateDealershipInput struct {
	Name     string
	Code     string
	Address  string
	Timezone string
}

type CreateDealershipAdminInput struct {
	DealershipID uuid.UUID
	Name         string
	Phone        *string
	Email        string
}

type CreateDealershipUserInput struct {
	DealershipID uuid.UUID
	Email        string
	Role         string
}

type CreateServiceTypeInput struct {
	Name                   string
	DefaultDurationMinutes int
	MinDurationMinutes     int
	MaxDurationMinutes     int
	IsActive               bool
}

type UpdateServiceTypeInput struct {
	Name                   *string
	DefaultDurationMinutes *int
	MinDurationMinutes     *int
	MaxDurationMinutes     *int
	IsActive               *bool
}

type CreateServiceBayInput struct {
	Code     string
	Name     string
	IsActive bool
}

type UpdateServiceBayInput struct {
	Code     *string
	Name     *string
	IsActive *bool
}

type CreateDealershipOperationTimeInput struct {
	DayOfWeek         int
	OpensAt, ClosesAt time.Duration
}
type UpdateDealershipOperationTimeInput struct {
	DayOfWeek         *int
	OpensAt, ClosesAt *time.Duration
}

type CreateServiceBayCapabilityInput struct{ BayCapabilityID uuid.UUID }
type UpdateServiceBayCapabilityInput struct{ BayCapabilityID *uuid.UUID }

type CreateCustomerInput struct {
	Name  string
	Phone string
	Email *string
}

type UpdateCustomerInput struct {
	Name         *string
	Phone        *string
	Email        *string
	EmailPresent bool
}

type CreateVehicleInput struct {
	VIN               *string
	RegistrationPlate *string
	Make              string
	Model             string
	ModelYear         *int
}

type UpdateVehicleInput struct {
	VINPresent               bool
	VIN                      *string
	RegistrationPlatePresent bool
	RegistrationPlate        *string
	Make                     *string
	Model                    *string
	ModelYearPresent         bool
	ModelYear                *int
}

type CreateServiceTypeRequiredSkillInput struct{ SkillID uuid.UUID }
type UpdateServiceTypeRequiredSkillInput struct{ SkillID *uuid.UUID }
type CreateServiceTypeRequiredBayCapabilityInput struct{ BayCapabilityID uuid.UUID }
type UpdateServiceTypeRequiredBayCapabilityInput struct{ BayCapabilityID *uuid.UUID }

// AuthUser is the scheduler-facing view of an account found in auth.
type AuthUser struct {
	ID       uuid.UUID
	Email    string
	FullName string
	Status   string
	Role     string
}

// SearchAuthUserByEmail resolves an auth account for assignment to a
// scheduler user. Auth admins/superadmins and scheduler admins may perform
// this lookup.
func (s *Service) SearchAuthUserByEmail(ctx context.Context, actorID uuid.UUID, email string) (AuthUser, error) {
	if actorID == uuid.Nil {
		return AuthUser{}, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if err := s.authorizeSearchAuthUser(ctx, actorID); err != nil {
		return AuthUser{}, err
	}

	email = strings.TrimSpace(email)
	if email == "" {
		return AuthUser{}, common.NewInvalidInputError("email_required", "email is required")
	}

	user, err := s.users.GetUserInfoByEmail(ctx, email)
	if err != nil || user.UserID == "" {
		return AuthUser{}, common.NewNotFoundError("auth_user_not_found", "auth user was not found")
	}
	userID, err := uuid.Parse(user.UserID)
	if err != nil {
		return AuthUser{}, common.NewNotFoundError("auth_user_not_found", "auth user was not found")
	}
	return AuthUser{
		ID:       userID,
		Email:    user.Email,
		FullName: user.FullName,
		Status:   user.Status,
		Role:     user.Role,
	}, nil
}

// CreateDealership creates an active dealership after checking the caller's
// current role and lifecycle status through auth's public module API.
func (s *Service) CreateDealership(ctx context.Context, actorID uuid.UUID, input CreateDealershipInput) (domain.Dealership, error) {
	if actorID == uuid.Nil {
		return domain.Dealership{}, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if err := s.authorizeCreate(ctx, actorID); err != nil {
		return domain.Dealership{}, err
	}
	dealership, err := domain.NewDealership(s.newID(), input.Name, input.Code, input.Address, input.Timezone, s.now())
	if err != nil {
		return domain.Dealership{}, invalidInputError(err)
	}
	if err := s.repository.Create(ctx, dealership); err != nil {
		if errors.Is(err, ErrDealershipCodeTaken) {
			return domain.Dealership{}, common.NewConflictError("dealership_code_taken", "dealership code already exists")
		}
		return domain.Dealership{}, err
	}
	return dealership, nil
}

// CreateDealershipAdmin creates one active scheduler user and its sole admin
// role after resolving both caller and target through auth's public contract.
func (s *Service) CreateDealershipAdmin(ctx context.Context, actorID uuid.UUID, input CreateDealershipAdminInput) (domain.DealershipAdmin, error) {
	if actorID == uuid.Nil {
		return domain.DealershipAdmin{}, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if err := s.authorizeCreateAdmin(ctx, actorID); err != nil {
		return domain.DealershipAdmin{}, err
	}
	authUser, err := s.requireActiveTargetAuthUser(ctx, input.Email)
	if err != nil {
		return domain.DealershipAdmin{}, err
	}
	adminEmail := authUser.Email
	admin, err := domain.NewDealershipAdmin(s.newID(), authUser.ID, input.DealershipID, input.Name, input.Phone, &adminEmail, s.now())
	if err != nil {
		return domain.DealershipAdmin{}, invalidAdminInputError(err)
	}
	repository, ok := s.repository.(AdminRepository)
	if !ok {
		return domain.DealershipAdmin{}, errors.New("dealership admin repository is not configured")
	}
	if err := repository.CreateDealershipAdmin(ctx, admin); err != nil {
		switch {
		case errors.Is(err, ErrAuthUserAlreadyAssigned):
			return domain.DealershipAdmin{}, common.NewConflictError("auth_user_already_assigned", "auth user is already assigned to a dealership user")
		case errors.Is(err, ErrDealershipNotFound):
			return domain.DealershipAdmin{}, common.NewNotFoundError("dealership_not_found", "dealership was not found")
		default:
			return domain.DealershipAdmin{}, err
		}
	}
	return admin, nil
}

// CreateDealershipUser grants a login-capable scheduler membership to an
// existing active auth account. The auth account's own role is never changed.
func (s *Service) CreateDealershipUser(ctx context.Context, actorID uuid.UUID, input CreateDealershipUserInput) (domain.DealershipUser, error) {
	if actorID == uuid.Nil {
		return domain.DealershipUser{}, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if input.DealershipID == uuid.Nil {
		return domain.DealershipUser{}, invalidDealershipUserInput("dealershipId", "dealership ID is required")
	}
	if strings.TrimSpace(input.Email) == "" {
		return domain.DealershipUser{}, invalidDealershipUserInput("email", "email is required")
	}
	if !validEmail(input.Email) {
		return domain.DealershipUser{}, invalidDealershipUserInput("email", "email must be a valid email address")
	}
	if input.Role != "admin" && input.Role != "dealer" && input.Role != "staff" {
		return domain.DealershipUser{}, invalidDealershipUserInput("role", "role must be admin, dealer, or staff")
	}
	if err := s.authorizeCreateDealershipUser(ctx, actorID, input.DealershipID); err != nil {
		return domain.DealershipUser{}, err
	}
	authUser, err := s.requireActiveTargetAuthUser(ctx, input.Email)
	if err != nil {
		return domain.DealershipUser{}, err
	}
	user, err := domain.NewDealershipUser(s.newID(), authUser.ID, input.DealershipID, authUser.FullName, authUser.Email, input.Role, s.now())
	if err != nil {
		return domain.DealershipUser{}, invalidDealershipUserDomainInput(err)
	}
	repository, ok := s.repository.(DealershipUserRepository)
	if !ok {
		return domain.DealershipUser{}, errors.New("dealership user repository is not configured")
	}
	if err := repository.CreateDealershipUser(ctx, user); err != nil {
		switch {
		case errors.Is(err, ErrAuthUserAlreadyAssigned):
			return domain.DealershipUser{}, common.NewConflictError("auth_user_already_assigned", "auth user is already assigned to a dealership user")
		case errors.Is(err, ErrDealershipNotFound):
			return domain.DealershipUser{}, common.NewNotFoundError("dealership_not_found", "dealership was not found")
		default:
			return domain.DealershipUser{}, err
		}
	}
	return user, nil
}

func (s *Service) CreateServiceType(ctx context.Context, actorID, dealershipID uuid.UUID, input CreateServiceTypeInput) (domain.ServiceType, error) {
	repository, err := s.authorizeServiceTypes(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceType{}, err
	}
	serviceType, err := domain.NewServiceType(
		s.newID(), dealershipID, input.Name,
		input.DefaultDurationMinutes,
		input.MinDurationMinutes,
		input.MaxDurationMinutes,
		input.IsActive,
		s.now(),
	)
	if err != nil {
		return domain.ServiceType{}, invalidServiceTypeInput(err)
	}
	if err := repository.CreateServiceType(ctx, serviceType); err != nil {
		if errors.Is(err, ErrServiceTypeNameTaken) {
			return domain.ServiceType{}, common.NewConflictError("service_type_name_taken", "a service type with this name already exists for the dealership")
		}
		return domain.ServiceType{}, err
	}
	return serviceType, nil
}

func (s *Service) GetServiceType(ctx context.Context, actorID, dealershipID, serviceTypeID uuid.UUID) (domain.ServiceType, error) {
	repository, err := s.authorizeServiceTypes(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceType{}, err
	}
	serviceType, err := repository.GetServiceType(ctx, dealershipID, serviceTypeID)
	if errors.Is(err, ErrServiceTypeNotFound) {
		return domain.ServiceType{}, common.NewNotFoundError("service_type_not_found", "service type was not found")
	}
	return serviceType, err
}

func (s *Service) ListServiceTypes(ctx context.Context, actorID, dealershipID uuid.UUID) ([]domain.ServiceType, error) {
	repository, err := s.authorizeServiceTypes(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	return repository.ListServiceTypes(ctx, dealershipID)
}

func (s *Service) UpdateServiceType(ctx context.Context, actorID, dealershipID, serviceTypeID uuid.UUID, input UpdateServiceTypeInput) (domain.ServiceType, error) {
	repository, err := s.authorizeServiceTypes(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceType{}, err
	}
	current, err := repository.GetServiceType(ctx, dealershipID, serviceTypeID)
	if errors.Is(err, ErrServiceTypeNotFound) {
		return domain.ServiceType{}, common.NewNotFoundError("service_type_not_found", "service type was not found")
	}
	if err != nil {
		return domain.ServiceType{}, err
	}
	updated, err := current.Update(
		valueOr(input.Name, current.Name()),
		valueOr(input.DefaultDurationMinutes, current.DefaultDurationMinutes()),
		valueOr(input.MinDurationMinutes, current.MinDurationMinutes()),
		valueOr(input.MaxDurationMinutes, current.MaxDurationMinutes()),
		valueOr(input.IsActive, current.IsActive()),
		s.now(),
	)
	if err != nil {
		return domain.ServiceType{}, invalidServiceTypeInput(err)
	}
	if err := repository.UpdateServiceType(ctx, updated); err != nil {
		if errors.Is(err, ErrServiceTypeNameTaken) {
			return domain.ServiceType{}, common.NewConflictError("service_type_name_taken", "a service type with this name already exists for the dealership")
		}
		if errors.Is(err, ErrServiceTypeNotFound) {
			return domain.ServiceType{}, common.NewNotFoundError("service_type_not_found", "service type was not found")
		}
		return domain.ServiceType{}, err
	}
	return updated, nil
}

func (s *Service) DeleteServiceType(ctx context.Context, actorID, dealershipID, serviceTypeID uuid.UUID) error {
	repository, err := s.authorizeServiceTypes(ctx, actorID, dealershipID)
	if err != nil {
		return err
	}
	err = repository.DeleteServiceType(ctx, dealershipID, serviceTypeID, s.now())
	switch {
	case errors.Is(err, ErrServiceTypeNotFound):
		return common.NewNotFoundError("service_type_not_found", "service type was not found")
	case errors.Is(err, ErrServiceTypeInUse):
		return common.NewConflictError("service_type_in_use", "service type is referenced by an appointment; set is_active to false instead")
	default:
		return err
	}
}

func (s *Service) CreateDealershipOperationTime(ctx context.Context, actorID, dealershipID uuid.UUID, input CreateDealershipOperationTimeInput) (domain.DealershipOperationTime, error) {
	repository, err := s.authorizeDealershipOperationTimes(ctx, actorID, dealershipID)
	if err != nil {
		return domain.DealershipOperationTime{}, err
	}
	operationTime, err := domain.NewDealershipOperationTime(s.newID(), dealershipID, input.DayOfWeek, input.OpensAt, input.ClosesAt, s.now())
	if err != nil {
		return domain.DealershipOperationTime{}, invalidOperationTimeInput(err)
	}
	if err := repository.CreateDealershipOperationTime(ctx, operationTime); err != nil {
		if errors.Is(err, ErrDealershipOperationTimeOverlaps) {
			return domain.DealershipOperationTime{}, common.NewConflictError("operation_time_overlaps", "operation time overlaps an existing interval")
		}
		return domain.DealershipOperationTime{}, err
	}
	return operationTime, nil
}

func (s *Service) ListDealershipOperationTimes(ctx context.Context, actorID, dealershipID uuid.UUID) ([]domain.DealershipOperationTime, error) {
	repository, err := s.authorizeDealershipOperationTimes(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	return repository.ListDealershipOperationTimes(ctx, dealershipID)
}

func (s *Service) UpdateDealershipOperationTime(ctx context.Context, actorID, dealershipID, operationTimeID uuid.UUID, input UpdateDealershipOperationTimeInput) (domain.DealershipOperationTime, error) {
	repository, err := s.authorizeDealershipOperationTimes(ctx, actorID, dealershipID)
	if err != nil {
		return domain.DealershipOperationTime{}, err
	}
	current, err := repository.GetDealershipOperationTime(ctx, dealershipID, operationTimeID)
	if errors.Is(err, ErrDealershipOperationTimeNotFound) {
		return domain.DealershipOperationTime{}, common.NewNotFoundError("operation_time_not_found", "operation time was not found")
	}
	if err != nil {
		return domain.DealershipOperationTime{}, err
	}
	updated, err := current.Update(valueOr(input.DayOfWeek, current.DayOfWeek()), valueOr(input.OpensAt, current.OpensAt()), valueOr(input.ClosesAt, current.ClosesAt()), s.now())
	if err != nil {
		return domain.DealershipOperationTime{}, invalidOperationTimeInput(err)
	}
	if err := repository.UpdateDealershipOperationTime(ctx, updated); err != nil {
		if errors.Is(err, ErrDealershipOperationTimeOverlaps) {
			return domain.DealershipOperationTime{}, common.NewConflictError("operation_time_overlaps", "operation time overlaps an existing interval")
		}
		if errors.Is(err, ErrDealershipOperationTimeNotFound) {
			return domain.DealershipOperationTime{}, common.NewNotFoundError("operation_time_not_found", "operation time was not found")
		}
		return domain.DealershipOperationTime{}, err
	}
	return updated, nil
}

func (s *Service) DeleteDealershipOperationTime(ctx context.Context, actorID, dealershipID, operationTimeID uuid.UUID) error {
	repository, err := s.authorizeDealershipOperationTimes(ctx, actorID, dealershipID)
	if err != nil {
		return err
	}
	err = repository.DeleteDealershipOperationTime(ctx, dealershipID, operationTimeID)
	if errors.Is(err, ErrDealershipOperationTimeNotFound) {
		return common.NewNotFoundError("operation_time_not_found", "operation time was not found")
	}
	return err
}

func (s *Service) authorizeDealershipOperationTimes(ctx context.Context, actorID, dealershipID uuid.UUID) (DealershipOperationTimeRepository, error) {
	if actorID == uuid.Nil {
		return nil, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if dealershipID == uuid.Nil {
		return nil, common.NewInvalidInputError("invalid_dealership_id", "dealership ID is required")
	}
	repository, ok := s.repository.(DealershipOperationTimeRepository)
	if !ok {
		return nil, errors.New("dealership operation time repository is not configured")
	}
	isAdmin, err := repository.IsActiveSchedulerAdminForDealership(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	if !isAdmin {
		return nil, common.NewForbiddenError("operation_time_access_forbidden", "you are not allowed to manage operation times for this dealership")
	}
	isActive, err := repository.IsActiveDealership(ctx, dealershipID)
	if err != nil {
		return nil, err
	}
	if !isActive {
		return nil, common.NewNotFoundError("dealership_not_found", "dealership was not found")
	}
	return repository, nil
}

func invalidOperationTimeInput(err error) common.Error {
	if errors.Is(err, domain.ErrInvalidOperationHours) {
		return common.Error{HttpErrorCode: 422, PublicError: "opens at must be earlier than closes at", ErrorSlug: "invalid_operation_time"}
	}
	return common.NewInvalidInputError("invalid_operation_time", "%s", err)
}

func (s *Service) CreateServiceTypeRequiredSkill(ctx context.Context, actorID, dealershipID, serviceTypeID uuid.UUID, input CreateServiceTypeRequiredSkillInput) (domain.ServiceTypeRequiredSkill, error) {
	repository, err := s.authorizeServiceTypeRequiredSkills(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceTypeRequiredSkill{}, err
	}
	requiredSkill, err := domain.NewServiceTypeRequiredSkill(s.newID(), serviceTypeID, input.SkillID, s.now())
	if err != nil {
		return domain.ServiceTypeRequiredSkill{}, invalidServiceTypeRequiredSkillInput(err)
	}
	result, err := repository.CreateServiceTypeRequiredSkill(ctx, dealershipID, requiredSkill)
	return result, serviceTypeRequiredSkillError(err)
}

func (s *Service) ListServiceTypeRequiredSkills(ctx context.Context, actorID, dealershipID, serviceTypeID uuid.UUID) ([]domain.ServiceTypeRequiredSkill, error) {
	repository, err := s.authorizeServiceTypeRequiredSkills(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	result, err := repository.ListServiceTypeRequiredSkills(ctx, dealershipID, serviceTypeID)
	if errors.Is(err, ErrServiceTypeNotFound) {
		return nil, common.NewNotFoundError("service_type_not_found", "service type was not found")
	}
	return result, err
}

func (s *Service) UpdateServiceTypeRequiredSkill(ctx context.Context, actorID, dealershipID, serviceTypeID, requiredSkillID uuid.UUID, input UpdateServiceTypeRequiredSkillInput) (domain.ServiceTypeRequiredSkill, error) {
	if input.SkillID == nil {
		return domain.ServiceTypeRequiredSkill{}, common.NewInvalidInputError("request_body_required", "skillId is required")
	}
	repository, err := s.authorizeServiceTypeRequiredSkills(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceTypeRequiredSkill{}, err
	}
	current, err := repository.GetServiceTypeRequiredSkill(ctx, dealershipID, serviceTypeID, requiredSkillID)
	if err != nil {
		return domain.ServiceTypeRequiredSkill{}, serviceTypeRequiredSkillError(err)
	}
	updated, err := current.WithSkill(*input.SkillID, s.now())
	if err != nil {
		return domain.ServiceTypeRequiredSkill{}, invalidServiceTypeRequiredSkillInput(err)
	}
	result, err := repository.UpdateServiceTypeRequiredSkill(ctx, dealershipID, updated)
	return result, serviceTypeRequiredSkillError(err)
}

func (s *Service) DeleteServiceTypeRequiredSkill(ctx context.Context, actorID, dealershipID, serviceTypeID, requiredSkillID uuid.UUID) error {
	repository, err := s.authorizeServiceTypeRequiredSkills(ctx, actorID, dealershipID)
	if err != nil {
		return err
	}
	err = repository.DeleteServiceTypeRequiredSkill(ctx, dealershipID, serviceTypeID, requiredSkillID)
	return serviceTypeRequiredSkillError(err)
}

func (s *Service) authorizeServiceTypeRequiredSkills(ctx context.Context, actorID, dealershipID uuid.UUID) (ServiceTypeRequiredSkillRepository, error) {
	if actorID == uuid.Nil {
		return nil, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if dealershipID == uuid.Nil {
		return nil, common.NewInvalidInputError("invalid_dealership_id", "dealership ID is required")
	}
	repository, ok := s.repository.(ServiceTypeRequiredSkillRepository)
	if !ok {
		return nil, errors.New("service type required skill repository is not configured")
	}
	isAdmin, err := repository.IsActiveSchedulerAdminForDealership(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	if !isAdmin {
		return nil, common.NewForbiddenError("service_type_required_skill_access_forbidden", "you are not allowed to manage required skills for this dealership")
	}
	return repository, nil
}

func serviceTypeRequiredSkillError(err error) error {
	switch {
	case errors.Is(err, ErrServiceTypeNotFound):
		return common.NewNotFoundError("service_type_not_found", "service type was not found")
	case errors.Is(err, ErrServiceTypeRequiredSkillNotFound):
		return common.NewNotFoundError("service_type_required_skill_not_found", "required skill was not found")
	case errors.Is(err, ErrSkillNotFound):
		return common.NewNotFoundError("skill_not_found", "skill was not found")
	case errors.Is(err, ErrServiceTypeRequiredSkillTaken):
		return common.NewConflictError("service_type_required_skill_taken", "the service type already requires this skill")
	default:
		return err
	}
}

func invalidServiceTypeRequiredSkillInput(err error) common.Error {
	return common.NewInvalidInputError("invalid_service_type_required_skill", "%s", err)
}

func (s *Service) CreateServiceTypeRequiredBayCapability(ctx context.Context, actorID, dealershipID, serviceTypeID uuid.UUID, input CreateServiceTypeRequiredBayCapabilityInput) (domain.ServiceTypeRequiredBayCapability, error) {
	repository, err := s.authorizeServiceTypeRequiredBayCapabilities(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceTypeRequiredBayCapability{}, err
	}
	requiredCapability, err := domain.NewServiceTypeRequiredBayCapability(s.newID(), serviceTypeID, input.BayCapabilityID, s.now())
	if err != nil {
		return domain.ServiceTypeRequiredBayCapability{}, invalidServiceTypeRequiredBayCapabilityInput(err)
	}
	result, err := repository.CreateServiceTypeRequiredBayCapability(ctx, dealershipID, requiredCapability)
	return result, serviceTypeRequiredBayCapabilityError(err)
}

func (s *Service) ListServiceTypeRequiredBayCapabilities(ctx context.Context, actorID, dealershipID, serviceTypeID uuid.UUID) ([]domain.ServiceTypeRequiredBayCapability, error) {
	repository, err := s.authorizeServiceTypeRequiredBayCapabilities(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	result, err := repository.ListServiceTypeRequiredBayCapabilities(ctx, dealershipID, serviceTypeID)
	return result, serviceTypeRequiredBayCapabilityError(err)
}

func (s *Service) UpdateServiceTypeRequiredBayCapability(ctx context.Context, actorID, dealershipID, serviceTypeID, requiredCapabilityID uuid.UUID, input UpdateServiceTypeRequiredBayCapabilityInput) (domain.ServiceTypeRequiredBayCapability, error) {
	if input.BayCapabilityID == nil {
		return domain.ServiceTypeRequiredBayCapability{}, common.NewInvalidInputError("request_body_required", "bayCapabilityId is required")
	}
	repository, err := s.authorizeServiceTypeRequiredBayCapabilities(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceTypeRequiredBayCapability{}, err
	}
	current, err := repository.GetServiceTypeRequiredBayCapability(ctx, dealershipID, serviceTypeID, requiredCapabilityID)
	if err != nil {
		return domain.ServiceTypeRequiredBayCapability{}, serviceTypeRequiredBayCapabilityError(err)
	}
	updated, err := current.WithBayCapability(*input.BayCapabilityID, s.now())
	if err != nil {
		return domain.ServiceTypeRequiredBayCapability{}, invalidServiceTypeRequiredBayCapabilityInput(err)
	}
	result, err := repository.UpdateServiceTypeRequiredBayCapability(ctx, dealershipID, updated)
	return result, serviceTypeRequiredBayCapabilityError(err)
}

func (s *Service) DeleteServiceTypeRequiredBayCapability(ctx context.Context, actorID, dealershipID, serviceTypeID, requiredCapabilityID uuid.UUID) error {
	repository, err := s.authorizeServiceTypeRequiredBayCapabilities(ctx, actorID, dealershipID)
	if err != nil {
		return err
	}
	err = repository.DeleteServiceTypeRequiredBayCapability(ctx, dealershipID, serviceTypeID, requiredCapabilityID)
	return serviceTypeRequiredBayCapabilityError(err)
}

func (s *Service) authorizeServiceTypeRequiredBayCapabilities(ctx context.Context, actorID, dealershipID uuid.UUID) (ServiceTypeRequiredBayCapabilityRepository, error) {
	if actorID == uuid.Nil {
		return nil, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if dealershipID == uuid.Nil {
		return nil, common.NewInvalidInputError("invalid_dealership_id", "dealership ID is required")
	}
	repository, ok := s.repository.(ServiceTypeRequiredBayCapabilityRepository)
	if !ok {
		return nil, errors.New("service type required bay capability repository is not configured")
	}
	isAdmin, err := repository.IsActiveSchedulerAdminForDealership(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	if !isAdmin {
		return nil, common.NewForbiddenError("service_type_required_bay_capability_access_forbidden", "you are not allowed to manage required bay capabilities for this dealership")
	}
	return repository, nil
}

func serviceTypeRequiredBayCapabilityError(err error) error {
	switch {
	case errors.Is(err, ErrServiceTypeNotFound):
		return common.NewNotFoundError("service_type_not_found", "service type was not found")
	case errors.Is(err, ErrServiceTypeRequiredBayCapabilityNotFound):
		return common.NewNotFoundError("service_type_required_bay_capability_not_found", "required bay capability was not found")
	case errors.Is(err, ErrBayCapabilityNotFound):
		return common.NewNotFoundError("bay_capability_not_found", "bay capability was not found")
	case errors.Is(err, ErrServiceTypeRequiredBayCapabilityTaken):
		return common.NewConflictError("service_type_required_bay_capability_taken", "the service type already requires this bay capability")
	default:
		return err
	}
}

func invalidServiceTypeRequiredBayCapabilityInput(err error) common.Error {
	return common.NewInvalidInputError("invalid_service_type_required_bay_capability", "%s", err)
}

func (s *Service) CreateServiceBay(ctx context.Context, actorID, dealershipID uuid.UUID, input CreateServiceBayInput) (domain.ServiceBay, error) {
	repository, err := s.authorizeServiceBays(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceBay{}, err
	}
	serviceBay, err := domain.NewServiceBay(s.newID(), dealershipID, input.Code, input.Name, input.IsActive, s.now())
	if err != nil {
		return domain.ServiceBay{}, invalidServiceBayInput(err)
	}
	if err := repository.CreateServiceBay(ctx, serviceBay); err != nil {
		if errors.Is(err, ErrServiceBayCodeTaken) {
			return domain.ServiceBay{}, common.NewConflictError("service_bay_code_taken", "a service bay with this code already exists for the dealership")
		}
		return domain.ServiceBay{}, err
	}
	return serviceBay, nil
}

func (s *Service) GetServiceBay(ctx context.Context, actorID, dealershipID, serviceBayID uuid.UUID) (domain.ServiceBay, error) {
	repository, err := s.authorizeServiceBays(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceBay{}, err
	}
	serviceBay, err := repository.GetServiceBay(ctx, dealershipID, serviceBayID)
	if errors.Is(err, ErrServiceBayNotFound) {
		return domain.ServiceBay{}, common.NewNotFoundError("service_bay_not_found", "service bay was not found")
	}
	return serviceBay, err
}

func (s *Service) ListServiceBays(ctx context.Context, actorID, dealershipID uuid.UUID, isActive *bool, limit, offset int) ([]domain.ServiceBay, error) {
	repository, err := s.authorizeServiceBays(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	if limit <= 0 || limit > 100 || offset < 0 {
		return nil, common.NewInvalidInputError("invalid_pagination", "limit must be between 1 and 100 and offset must not be negative")
	}
	return repository.ListServiceBays(ctx, dealershipID, isActive, limit, offset)
}

func (s *Service) UpdateServiceBay(ctx context.Context, actorID, dealershipID, serviceBayID uuid.UUID, input UpdateServiceBayInput) (domain.ServiceBay, error) {
	repository, err := s.authorizeServiceBays(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceBay{}, err
	}
	current, err := repository.GetServiceBay(ctx, dealershipID, serviceBayID)
	if errors.Is(err, ErrServiceBayNotFound) {
		return domain.ServiceBay{}, common.NewNotFoundError("service_bay_not_found", "service bay was not found")
	}
	if err != nil {
		return domain.ServiceBay{}, err
	}
	updated, err := current.Update(valueOr(input.Code, current.Code()), valueOr(input.Name, current.Name()), valueOr(input.IsActive, current.IsActive()), s.now())
	if err != nil {
		return domain.ServiceBay{}, invalidServiceBayInput(err)
	}
	if err := repository.UpdateServiceBay(ctx, updated); err != nil {
		switch {
		case errors.Is(err, ErrServiceBayCodeTaken):
			return domain.ServiceBay{}, common.NewConflictError("service_bay_code_taken", "a service bay with this code already exists for the dealership")
		case errors.Is(err, ErrServiceBayNotFound):
			return domain.ServiceBay{}, common.NewNotFoundError("service_bay_not_found", "service bay was not found")
		default:
			return domain.ServiceBay{}, err
		}
	}
	return updated, nil
}

func (s *Service) DeleteServiceBay(ctx context.Context, actorID, dealershipID, serviceBayID uuid.UUID) error {
	repository, err := s.authorizeServiceBays(ctx, actorID, dealershipID)
	if err != nil {
		return err
	}
	err = repository.DeleteServiceBay(ctx, dealershipID, serviceBayID, s.now())
	switch {
	case errors.Is(err, ErrServiceBayNotFound):
		return common.NewNotFoundError("service_bay_not_found", "service bay was not found")
	case errors.Is(err, ErrServiceBayInUse):
		return common.NewConflictError("service_bay_in_use", "service bay is referenced by an appointment; set is_active to false instead")
	default:
		return err
	}
}

func (s *Service) CreateServiceBayCapability(ctx context.Context, actorID, dealershipID, serviceBayID uuid.UUID, input CreateServiceBayCapabilityInput) (domain.ServiceBayCapability, error) {
	repository, err := s.authorizeServiceBayCapabilities(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceBayCapability{}, err
	}
	capability, err := domain.NewServiceBayCapability(s.newID(), serviceBayID, input.BayCapabilityID, s.now())
	if err != nil {
		return domain.ServiceBayCapability{}, invalidServiceBayCapabilityInput(err)
	}
	result, err := repository.CreateServiceBayCapability(ctx, dealershipID, capability)
	return result, serviceBayCapabilityError(err)
}

func (s *Service) ListServiceBayCapabilities(ctx context.Context, actorID, dealershipID, serviceBayID uuid.UUID) ([]domain.ServiceBayCapability, error) {
	repository, err := s.authorizeServiceBayCapabilities(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	result, err := repository.ListServiceBayCapabilities(ctx, dealershipID, serviceBayID)
	return result, serviceBayCapabilityError(err)
}

func (s *Service) UpdateServiceBayCapability(ctx context.Context, actorID, dealershipID, serviceBayID, serviceBayCapabilityID uuid.UUID, input UpdateServiceBayCapabilityInput) (domain.ServiceBayCapability, error) {
	if input.BayCapabilityID == nil {
		return domain.ServiceBayCapability{}, common.NewInvalidInputError("request_body_required", "bayCapabilityId is required")
	}
	repository, err := s.authorizeServiceBayCapabilities(ctx, actorID, dealershipID)
	if err != nil {
		return domain.ServiceBayCapability{}, err
	}
	current, err := repository.GetServiceBayCapability(ctx, dealershipID, serviceBayID, serviceBayCapabilityID)
	if err != nil {
		return domain.ServiceBayCapability{}, serviceBayCapabilityError(err)
	}
	updated, err := current.WithBayCapability(*input.BayCapabilityID, s.now())
	if err != nil {
		return domain.ServiceBayCapability{}, invalidServiceBayCapabilityInput(err)
	}
	result, err := repository.UpdateServiceBayCapability(ctx, dealershipID, updated)
	return result, serviceBayCapabilityError(err)
}

func (s *Service) DeleteServiceBayCapability(ctx context.Context, actorID, dealershipID, serviceBayID, serviceBayCapabilityID uuid.UUID) error {
	repository, err := s.authorizeServiceBayCapabilities(ctx, actorID, dealershipID)
	if err != nil {
		return err
	}
	err = repository.DeleteServiceBayCapability(ctx, dealershipID, serviceBayID, serviceBayCapabilityID)
	return serviceBayCapabilityError(err)
}

func (s *Service) authorizeServiceBayCapabilities(ctx context.Context, actorID, dealershipID uuid.UUID) (ServiceBayCapabilityRepository, error) {
	if actorID == uuid.Nil {
		return nil, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if dealershipID == uuid.Nil {
		return nil, common.NewInvalidInputError("invalid_dealership_id", "dealership ID is required")
	}
	repository, ok := s.repository.(ServiceBayCapabilityRepository)
	if !ok {
		return nil, errors.New("service bay capability repository is not configured")
	}
	allowed, err := repository.IsActiveSchedulerAdminForDealership(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, common.NewForbiddenError("service_bay_capability_access_forbidden", "active dealership admin access is required")
	}
	return repository, nil
}

func serviceBayCapabilityError(err error) error {
	switch {
	case errors.Is(err, ErrServiceBayNotFound):
		return common.NewNotFoundError("service_bay_not_found", "service bay was not found")
	case errors.Is(err, ErrServiceBayCapabilityNotFound):
		return common.NewNotFoundError("service_bay_capability_not_found", "service bay capability was not found")
	case errors.Is(err, ErrBayCapabilityNotFound):
		return common.NewNotFoundError("bay_capability_not_found", "bay capability was not found")
	case errors.Is(err, ErrServiceBayCapabilityTaken):
		return common.NewConflictError("service_bay_capability_taken", "the service bay already has this capability")
	default:
		return err
	}
}

func invalidServiceBayCapabilityInput(err error) common.Error {
	return common.NewInvalidInputError("invalid_service_bay_capability", "%s", err)
}

func (s *Service) authorizeServiceBays(ctx context.Context, actorID, dealershipID uuid.UUID) (ServiceBayRepository, error) {
	if actorID == uuid.Nil {
		return nil, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if dealershipID == uuid.Nil {
		return nil, common.NewInvalidInputError("invalid_dealership_id", "dealership ID is required")
	}
	repository, ok := s.repository.(ServiceBayRepository)
	if !ok {
		return nil, errors.New("service bay repository is not configured")
	}
	isAdmin, err := repository.IsActiveSchedulerAdminForDealership(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	if !isAdmin {
		return nil, common.NewForbiddenError("service_bay_access_forbidden", "you are not allowed to manage service bays for this dealership")
	}
	return repository, nil
}

func (s *Service) authorizeServiceTypes(ctx context.Context, actorID, dealershipID uuid.UUID) (ServiceTypeRepository, error) {
	if actorID == uuid.Nil {
		return nil, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	if dealershipID == uuid.Nil {
		return nil, common.NewInvalidInputError("invalid_dealership_id", "dealership ID is required")
	}
	repository, ok := s.repository.(ServiceTypeRepository)
	if !ok {
		return nil, errors.New("service type repository is not configured")
	}
	isAdmin, err := repository.IsActiveSchedulerAdminForDealership(ctx, actorID, dealershipID)
	if err != nil {
		return nil, err
	}
	if !isAdmin {
		return nil, common.NewForbiddenError("service_type_access_forbidden", "you are not allowed to manage service types for this dealership")
	}
	return repository, nil
}

// CreateCustomer adds a global customer record. Customer records are not
// owned by a dealership in the current schema.
func (s *Service) CreateCustomer(ctx context.Context, actorID uuid.UUID, input CreateCustomerInput) (domain.Customer, error) {
	repository, err := s.authorizeCustomers(ctx, actorID)
	if err != nil {
		return domain.Customer{}, err
	}
	name, phone, email, err := normalizeCustomerInput(input.Name, input.Phone, input.Email)
	if err != nil {
		return domain.Customer{}, err
	}
	customer, err := domain.NewCustomer(s.newID(), name, phone, email, s.now())
	if err != nil {
		return domain.Customer{}, common.NewInvalidInputError("invalid_request", "customer name is required")
	}
	customer, err = repository.CreateCustomer(ctx, customer)
	return customer, customerError(err)
}

func (s *Service) GetCustomer(ctx context.Context, actorID, customerID uuid.UUID) (domain.Customer, error) {
	repository, err := s.authorizeCustomers(ctx, actorID)
	if err != nil {
		return domain.Customer{}, err
	}
	if customerID == uuid.Nil {
		return domain.Customer{}, common.NewInvalidInputError("invalid_request", "customer ID must be a valid UUID")
	}
	customer, err := repository.GetCustomer(ctx, customerID)
	return customer, customerError(err)
}

func (s *Service) UpdateCustomer(ctx context.Context, actorID, customerID uuid.UUID, input UpdateCustomerInput) (domain.Customer, error) {
	repository, err := s.authorizeCustomers(ctx, actorID)
	if err != nil {
		return domain.Customer{}, err
	}
	if customerID == uuid.Nil {
		return domain.Customer{}, common.NewInvalidInputError("invalid_request", "customer ID must be a valid UUID")
	}
	if input.Name == nil && input.Phone == nil && !input.EmailPresent {
		return domain.Customer{}, common.NewInvalidInputError("invalid_request", "at least one field is required")
	}
	existing, err := repository.GetCustomer(ctx, customerID)
	if err != nil {
		return domain.Customer{}, customerError(err)
	}
	name := existing.Name()
	if input.Name != nil {
		name = *input.Name
	}
	phone := existing.Phone()
	if input.Phone != nil {
		phone = *input.Phone
	}
	email := existing.Email()
	if input.EmailPresent {
		email = input.Email
	}
	name, phone, email, err = normalizeCustomerInput(name, phone, email)
	if err != nil {
		return domain.Customer{}, err
	}
	updated, err := existing.Update(name, phone, email, s.now())
	if err != nil {
		return domain.Customer{}, common.NewInvalidInputError("invalid_request", "customer name is required")
	}
	updated, err = repository.UpdateCustomer(ctx, updated)
	return updated, customerError(err)
}

func (s *Service) SearchCustomers(ctx context.Context, actorID uuid.UUID, phone, email *string) ([]domain.Customer, error) {
	repository, err := s.authorizeCustomers(ctx, actorID)
	if err != nil {
		return nil, err
	}
	if (phone == nil && email == nil) || (phone != nil && email != nil) {
		return nil, common.NewInvalidInputError("invalid_request", "exactly one of phone or email is required")
	}
	if phone != nil {
		normalizedPhone, err := normalizePhone(*phone)
		if err != nil {
			return nil, err
		}
		customer, err := repository.GetCustomerByPhone(ctx, normalizedPhone)
		if errors.Is(err, ErrCustomerNotFound) {
			return []domain.Customer{}, nil
		}
		if err != nil {
			return nil, customerError(err)
		}
		return []domain.Customer{customer}, nil
	}
	normalizedEmail, err := normalizeEmail(*email)
	if err != nil {
		return nil, err
	}
	customer, err := repository.GetCustomerByEmail(ctx, normalizedEmail)
	if errors.Is(err, ErrCustomerNotFound) {
		return []domain.Customer{}, nil
	}
	if err != nil {
		return nil, customerError(err)
	}
	return []domain.Customer{customer}, nil
}

func (s *Service) authorizeCustomers(ctx context.Context, actorID uuid.UUID) (CustomerRepository, error) {
	if actorID == uuid.Nil {
		return nil, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	repository, ok := s.repository.(CustomerRepository)
	if !ok {
		return nil, errors.New("customer repository is not configured")
	}
	allowed, err := repository.IsActiveCustomerEmployee(ctx, actorID)
	if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, common.NewForbiddenError("customer_access_forbidden", "you are not allowed to manage customers")
	}
	return repository, nil
}

func normalizeCustomerInput(name, phone string, email *string) (string, string, *string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", "", nil, common.NewInvalidInputError("invalid_request", "customer name is required")
	}
	normalizedPhone, err := normalizePhone(phone)
	if err != nil {
		return "", "", nil, err
	}
	if email == nil {
		return name, normalizedPhone, nil, nil
	}
	normalizedEmail, err := normalizeEmail(*email)
	if err != nil {
		return "", "", nil, err
	}
	return name, normalizedPhone, &normalizedEmail, nil
}

func normalizePhone(value string) (string, error) {
	value = strings.TrimSpace(value)
	value = strings.NewReplacer(" ", "", "-", "", "(", "", ")", "", ".", "").Replace(value)
	if len(value) < 9 || len(value) > 16 || value[0] != '+' || value[1] == '0' {
		return "", common.NewInvalidInputError("invalid_request", "phone must be a valid E.164 number")
	}
	for _, character := range value[1:] {
		if character < '0' || character > '9' {
			return "", common.NewInvalidInputError("invalid_request", "phone must be a valid E.164 number")
		}
	}
	return value, nil
}

func normalizeEmail(value string) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	parsed, err := mail.ParseAddress(value)
	if err != nil || parsed.Address != value {
		return "", common.NewInvalidInputError("invalid_request", "email must be a valid email address")
	}
	return value, nil
}

func customerError(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, ErrCustomerNotFound):
		return common.NewNotFoundError("customer_not_found", "customer was not found")
	case errors.Is(err, ErrCustomerPhoneTaken):
		return common.NewConflictError("customer_phone_already_exists", "a customer with this phone already exists")
	case errors.Is(err, ErrCustomerEmailTaken):
		return common.NewConflictError("customer_email_already_exists", "a customer with this email already exists")
	default:
		return err
	}
}

func (s *Service) CreateVehicle(ctx context.Context, actorID, customerID uuid.UUID, input CreateVehicleInput) (domain.Vehicle, error) {
	repository, dealershipID, err := s.authorizeVehicleManager(ctx, actorID)
	if err != nil {
		return domain.Vehicle{}, err
	}
	vehicle, err := domain.NewVehicle(s.newID(), customerID, input.VIN, input.RegistrationPlate, input.Make, input.Model, input.ModelYear, s.now())
	if err != nil {
		return domain.Vehicle{}, vehicleInputError(err)
	}
	if err := repository.CreateVehicle(ctx, dealershipID, vehicle); err != nil {
		return domain.Vehicle{}, vehicleError(err)
	}
	return vehicle, nil
}

func (s *Service) GetVehicle(ctx context.Context, actorID, vehicleID uuid.UUID) (domain.Vehicle, error) {
	repository, dealershipID, err := s.authorizeVehicleManager(ctx, actorID)
	if err != nil {
		return domain.Vehicle{}, err
	}
	vehicle, err := repository.GetVehicle(ctx, vehicleID)
	if err != nil {
		return domain.Vehicle{}, vehicleError(err)
	}
	if err := s.authorizeVehicleCustomer(ctx, repository, dealershipID, vehicle.CustomerID()); err != nil {
		return domain.Vehicle{}, err
	}
	return vehicle, nil
}

func (s *Service) ListCustomerVehicles(ctx context.Context, actorID, customerID uuid.UUID) ([]domain.Vehicle, error) {
	repository, dealershipID, err := s.authorizeVehicleManager(ctx, actorID)
	if err != nil {
		return nil, err
	}
	if _, err := repository.GetCustomer(ctx, customerID); err != nil {
		return nil, vehicleError(err)
	}
	if err := s.authorizeVehicleCustomer(ctx, repository, dealershipID, customerID); err != nil {
		return nil, err
	}
	vehicles, err := repository.ListCustomerVehicles(ctx, customerID)
	if err != nil {
		return nil, vehicleError(err)
	}
	return vehicles, nil
}

func (s *Service) UpdateVehicle(ctx context.Context, actorID, vehicleID uuid.UUID, input UpdateVehicleInput) (domain.Vehicle, error) {
	repository, dealershipID, err := s.authorizeVehicleManager(ctx, actorID)
	if err != nil {
		return domain.Vehicle{}, err
	}
	vehicle, err := repository.GetVehicle(ctx, vehicleID)
	if err != nil {
		return domain.Vehicle{}, vehicleError(err)
	}
	if err := s.authorizeVehicleCustomer(ctx, repository, dealershipID, vehicle.CustomerID()); err != nil {
		return domain.Vehicle{}, err
	}
	vin := vehicle.VIN()
	if input.VINPresent {
		vin = input.VIN
	}
	registrationPlate := vehicle.RegistrationPlate()
	if input.RegistrationPlatePresent {
		registrationPlate = input.RegistrationPlate
	}
	make := valueOr(input.Make, vehicle.Make())
	model := valueOr(input.Model, vehicle.Model())
	modelYear := vehicle.ModelYear()
	if input.ModelYearPresent {
		modelYear = input.ModelYear
	}
	updated, err := vehicle.Update(vin, registrationPlate, make, model, modelYear, s.now())
	if err != nil {
		return domain.Vehicle{}, vehicleInputError(err)
	}
	if err := repository.UpdateVehicle(ctx, updated); err != nil {
		return domain.Vehicle{}, vehicleError(err)
	}
	return updated, nil
}

func (s *Service) DeleteVehicle(ctx context.Context, actorID, vehicleID uuid.UUID) error {
	repository, dealershipID, err := s.authorizeVehicleManager(ctx, actorID)
	if err != nil {
		return err
	}
	vehicle, err := repository.GetVehicle(ctx, vehicleID)
	if err != nil {
		return vehicleError(err)
	}
	if err := s.authorizeVehicleCustomer(ctx, repository, dealershipID, vehicle.CustomerID()); err != nil {
		return err
	}
	// TODO: once preparation-history records exist, reject affected vehicles
	// with common.NewConflictError("vehicle_has_preparation_history", ...).
	return vehicleError(repository.DeleteVehicle(ctx, vehicleID, s.now()))
}

func (s *Service) authorizeVehicleManager(ctx context.Context, actorID uuid.UUID) (VehicleRepository, uuid.UUID, error) {
	if actorID == uuid.Nil {
		return nil, uuid.Nil, common.NewUnauthorizedError("authentication_required", "authentication required")
	}
	repository, ok := s.repository.(VehicleRepository)
	if !ok {
		return nil, uuid.Nil, errors.New("vehicle repository is not configured")
	}
	dealershipID, err := repository.GetActiveVehicleManagerDealership(ctx, actorID)
	if err != nil {
		return nil, uuid.Nil, common.NewForbiddenError("vehicle_access_forbidden", "you are not allowed to manage vehicles")
	}
	return repository, dealershipID, nil
}

func (s *Service) authorizeVehicleCustomer(ctx context.Context, repository VehicleRepository, dealershipID, customerID uuid.UUID) error {
	belongs, err := repository.CustomerBelongsToDealership(ctx, customerID, dealershipID)
	if err != nil {
		return vehicleError(err)
	}
	if !belongs {
		return common.NewForbiddenError("vehicle_access_forbidden", "you are not allowed to manage vehicles for this customer")
	}
	return nil
}

func vehicleInputError(err error) error {
	switch {
	case errors.Is(err, domain.ErrVehicleMakeRequired), errors.Is(err, domain.ErrVehicleModelRequired), errors.Is(err, domain.ErrVehicleIdentity), errors.Is(err, domain.ErrVehicleModelYear):
		return common.NewInvalidInputError("invalid_vehicle", "%s", err.Error())
	default:
		return err
	}
}

func vehicleError(err error) error {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, ErrVehicleNotFound):
		return common.NewNotFoundError("vehicle_not_found", "vehicle was not found")
	case errors.Is(err, ErrCustomerNotFound):
		return common.NewNotFoundError("customer_not_found", "customer was not found")
	case errors.Is(err, ErrVehicleVINTaken):
		return common.NewConflictError("vehicle_vin_already_exists", "a vehicle with this VIN already exists")
	case errors.Is(err, ErrVehicleCustomerForbidden):
		return common.NewForbiddenError("vehicle_access_forbidden", "you are not allowed to manage vehicles for this customer")
	default:
		return err
	}
}

func valueOr[T any](value *T, fallback T) T {
	if value == nil {
		return fallback
	}
	return *value
}

func (s *Service) authorizeCreate(ctx context.Context, actorID uuid.UUID) error {
	user, err := s.users.GetUserInfo(ctx, actorID)
	if err != nil || user.UserID == "" || user.UserID != actorID.String() {
		return common.NewForbiddenError("dealership_create_forbidden", "you are not allowed to create dealerships")
	}
	if user.Status != "active" || (user.Role != "superadmin" && user.Role != "admin") {
		return common.NewForbiddenError("dealership_create_forbidden", "you are not allowed to create dealerships")
	}
	return nil
}

func (s *Service) authorizeCreateAdmin(ctx context.Context, actorID uuid.UUID) error {
	user, err := s.users.GetUserInfo(ctx, actorID)
	if err != nil || user.UserID == "" || user.UserID != actorID.String() {
		return common.NewForbiddenError("dealership_admin_create_forbidden", "you are not allowed to create dealership admins")
	}
	if user.Status != "active" || (user.Role != "superadmin" && user.Role != "admin") {
		return common.NewForbiddenError("dealership_admin_create_forbidden", "you are not allowed to create dealership admins")
	}
	return nil
}

func (s *Service) authorizeCreateDealershipUser(ctx context.Context, actorID, dealershipID uuid.UUID) error {
	user, err := s.users.GetUserInfo(ctx, actorID)
	if err != nil || user.UserID == "" || user.UserID != actorID.String() || user.Status != "active" {
		return common.NewForbiddenError("dealership_user_create_forbidden", "you are not allowed to create dealership users")
	}
	if user.Role == "superadmin" || user.Role == "admin" {
		return nil
	}
	authorizer, ok := s.repository.(DealershipSchedulerAdminAuthorizer)
	if !ok {
		return errors.New("dealership scheduler admin authorization repository is not configured")
	}
	isAdmin, err := authorizer.IsActiveSchedulerAdminForDealership(ctx, actorID, dealershipID)
	if err != nil {
		return err
	}
	if !isAdmin {
		return common.NewForbiddenError("dealership_user_create_forbidden", "you are not allowed to create dealership users")
	}
	return nil
}

func (s *Service) authorizeSearchAuthUser(ctx context.Context, actorID uuid.UUID) error {
	user, err := s.users.GetUserInfo(ctx, actorID)
	if err != nil || user.UserID == "" || user.UserID != actorID.String() || user.Status != "active" {
		return common.NewForbiddenError("auth_user_search_forbidden", "you are not allowed to search auth users")
	}
	if user.Role == "superadmin" || user.Role == "admin" {
		return nil
	}

	authorizer, ok := s.repository.(SchedulerAdminAuthorizer)
	if !ok {
		return errors.New("scheduler admin authorization repository is not configured")
	}
	isAdmin, err := authorizer.IsActiveSchedulerAdmin(ctx, actorID)
	if err != nil {
		return err
	}
	if !isAdmin {
		return common.NewForbiddenError("auth_user_search_forbidden", "you are not allowed to search auth users")
	}
	return nil
}

type activeAuthUser struct {
	ID       uuid.UUID
	Email    string
	FullName string
}

func (s *Service) requireActiveTargetAuthUser(ctx context.Context, email string) (activeAuthUser, error) {
	user, err := s.users.GetUserInfoByEmail(ctx, email)
	if err != nil || user.UserID == "" {
		return activeAuthUser{}, common.NewNotFoundError("auth_user_not_found", "auth user was not found")
	}
	authUserID, err := uuid.Parse(user.UserID)
	if err != nil {
		return activeAuthUser{}, common.NewNotFoundError("auth_user_not_found", "auth user was not found")
	}
	if user.Status != "active" {
		return activeAuthUser{}, common.NewInvalidInputError("auth_user_inactive", "auth user must be active")
	}
	return activeAuthUser{ID: authUserID, Email: user.Email, FullName: user.FullName}, nil
}

func invalidDealershipUserInput(field, message string) common.Error {
	return common.NewInvalidInputError("invalid_dealership_user", "invalid dealership user").WithDetails([]common.ErrorDetails{{
		EntityType: "input", EntityID: field, ErrorSlug: "invalid_dealership_user", Message: message,
	}})
}

func invalidDealershipUserDomainInput(err error) common.Error {
	field := "dealershipUser"
	switch {
	case errors.Is(err, domain.ErrAuthUserIDRequired):
		field = "authUserId"
	case errors.Is(err, domain.ErrDealershipIDRequired):
		field = "dealershipId"
	case errors.Is(err, domain.ErrUserNameRequired):
		field = "name"
	case errors.Is(err, domain.ErrUserEmailRequired), errors.Is(err, domain.ErrInvalidUserEmail):
		field = "email"
	case errors.Is(err, domain.ErrInvalidUserRole):
		field = "role"
	}
	return invalidDealershipUserInput(field, err.Error())
}

func validEmail(value string) bool {
	normalized := strings.ToLower(strings.TrimSpace(value))
	address, err := mail.ParseAddress(normalized)
	return err == nil && address.Address == normalized
}

func invalidInputError(err error) common.Error {
	slug := "invalid_dealership"
	field := "dealership"
	switch {
	case errors.Is(err, domain.ErrNameRequired):
		field = "name"
	case errors.Is(err, domain.ErrCodeRequired):
		field = "code"
	case errors.Is(err, domain.ErrAddressRequired):
		field = "address"
	case errors.Is(err, domain.ErrTimezoneRequired), errors.Is(err, domain.ErrInvalidTimezone):
		field = "timezone"
	}
	return common.NewInvalidInputError(slug, "invalid dealership").WithDetails([]common.ErrorDetails{{
		EntityType: "input",
		EntityID:   field,
		ErrorSlug:  slug,
		Message:    err.Error(),
	}})
}

func invalidAdminInputError(err error) common.Error {
	field := "dealershipAdmin"
	switch {
	case errors.Is(err, domain.ErrAuthUserIDRequired):
		field = "authUserId"
	case errors.Is(err, domain.ErrDealershipIDRequired):
		field = "dealershipId"
	case errors.Is(err, domain.ErrAdminNameRequired):
		field = "name"
	case errors.Is(err, domain.ErrInvalidAdminPhone):
		field = "phone"
	case errors.Is(err, domain.ErrInvalidAdminEmail):
		field = "email"
	}
	return common.NewInvalidInputError("invalid_dealership_admin", "invalid dealership admin").WithDetails([]common.ErrorDetails{{
		EntityType: "input",
		EntityID:   field,
		ErrorSlug:  "invalid_dealership_admin",
		Message:    err.Error(),
	}})
}

func invalidServiceTypeInput(err error) common.Error {
	field := "serviceType"
	switch {
	case errors.Is(err, domain.ErrServiceTypeNameRequired):
		field = "name"
	case errors.Is(err, domain.ErrDurationMustBePositive), errors.Is(err, domain.ErrDurationRangeInvalid):
		field = "durationMinutes"
	}
	return common.NewInvalidInputError("invalid_service_type", "invalid service type").WithDetails([]common.ErrorDetails{{
		EntityType: "input", EntityID: field, ErrorSlug: "invalid_service_type", Message: err.Error(),
	}})
}

func invalidServiceBayInput(err error) common.Error {
	field := "serviceBay"
	switch {
	case errors.Is(err, domain.ErrServiceBayCodeRequired):
		field = "code"
	case errors.Is(err, domain.ErrServiceBayNameRequired):
		field = "name"
	}
	return common.NewInvalidInputError("invalid_service_bay", "invalid service bay").WithDetails([]common.ErrorDetails{{
		EntityType: "input", EntityID: field, ErrorSlug: "invalid_service_bay", Message: err.Error(),
	}})
}
