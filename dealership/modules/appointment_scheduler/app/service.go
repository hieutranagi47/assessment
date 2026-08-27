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
	ErrDealershipCodeTaken              = errors.New("dealership code already exists")
	ErrAuthUserAlreadyAssigned          = errors.New("auth user already assigned")
	ErrDealershipNotFound               = errors.New("dealership not found")
	ErrServiceTypeNameTaken             = errors.New("service type name already exists")
	ErrServiceTypeNotFound              = errors.New("service type not found")
	ErrServiceTypeInUse                 = errors.New("service type is referenced by an appointment")
	ErrServiceBayCodeTaken              = errors.New("service bay code already exists")
	ErrServiceBayNotFound               = errors.New("service bay not found")
	ErrServiceBayInUse                  = errors.New("service bay is referenced by an appointment")
	ErrServiceTypeRequiredSkillNotFound = errors.New("service type required skill not found")
	ErrServiceTypeRequiredSkillTaken    = errors.New("service type already requires this skill")
	ErrSkillNotFound                    = errors.New("skill not found")
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

type CreateServiceTypeRequiredSkillInput struct{ SkillID uuid.UUID }
type UpdateServiceTypeRequiredSkillInput struct{ SkillID *uuid.UUID }

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
