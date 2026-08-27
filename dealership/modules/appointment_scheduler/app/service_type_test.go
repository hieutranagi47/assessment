package app

import (
	"context"
	"errors"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/auth/api/module/client"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type requiredSkillRepositoryStub struct {
	admin       bool
	serviceType domain.ServiceType
	required    domain.ServiceTypeRequiredSkill
	createErr   error
	deleteErr   error
}

func (r *requiredSkillRepositoryStub) Create(context.Context, domain.Dealership) error { return nil }
func (r *requiredSkillRepositoryStub) IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return r.admin, nil
}
func (r *requiredSkillRepositoryStub) CreateServiceTypeRequiredSkill(_ context.Context, dealershipID uuid.UUID, required domain.ServiceTypeRequiredSkill) (domain.ServiceTypeRequiredSkill, error) {
	if r.serviceType.DealershipID() != dealershipID || r.serviceType.ID() != required.ServiceTypeID() {
		return domain.ServiceTypeRequiredSkill{}, ErrServiceTypeNotFound
	}
	if r.createErr != nil {
		return domain.ServiceTypeRequiredSkill{}, r.createErr
	}
	r.required = required
	return required, nil
}
func (r *requiredSkillRepositoryStub) GetServiceTypeRequiredSkill(_ context.Context, dealershipID, serviceTypeID, requiredID uuid.UUID) (domain.ServiceTypeRequiredSkill, error) {
	if r.serviceType.DealershipID() != dealershipID || r.serviceType.ID() != serviceTypeID || r.required.ID() != requiredID {
		return domain.ServiceTypeRequiredSkill{}, ErrServiceTypeRequiredSkillNotFound
	}
	return r.required, nil
}
func (r *requiredSkillRepositoryStub) ListServiceTypeRequiredSkills(_ context.Context, dealershipID, serviceTypeID uuid.UUID) ([]domain.ServiceTypeRequiredSkill, error) {
	if r.serviceType.DealershipID() != dealershipID || r.serviceType.ID() != serviceTypeID {
		return nil, ErrServiceTypeNotFound
	}
	return []domain.ServiceTypeRequiredSkill{r.required}, nil
}
func (r *requiredSkillRepositoryStub) UpdateServiceTypeRequiredSkill(_ context.Context, dealershipID uuid.UUID, required domain.ServiceTypeRequiredSkill) (domain.ServiceTypeRequiredSkill, error) {
	if r.serviceType.DealershipID() != dealershipID || r.required.ID() != required.ID() {
		return domain.ServiceTypeRequiredSkill{}, ErrServiceTypeRequiredSkillNotFound
	}
	if r.createErr != nil {
		return domain.ServiceTypeRequiredSkill{}, r.createErr
	}
	r.required = required
	return required, nil
}
func (r *requiredSkillRepositoryStub) DeleteServiceTypeRequiredSkill(_ context.Context, dealershipID, serviceTypeID, requiredID uuid.UUID) error {
	if r.serviceType.DealershipID() != dealershipID || r.serviceType.ID() != serviceTypeID || r.required.ID() != requiredID {
		return ErrServiceTypeRequiredSkillNotFound
	}
	return r.deleteErr
}

func TestServiceTypeRequiredSkillAuthorizationOwnershipDuplicateAndDeletion(t *testing.T) {
	actor, dealershipID, otherDealershipID := uuid.New(), uuid.New(), uuid.New()
	serviceType, err := domain.NewServiceType(uuid.New(), dealershipID, "Oil change", 60, 30, 90, true, time.Now())
	require.NoError(t, err)
	repository := &requiredSkillRepositoryStub{admin: true, serviceType: serviceType}
	service := NewService(repository, userInfoStub{})
	required, err := service.CreateServiceTypeRequiredSkill(context.Background(), actor, dealershipID, serviceType.ID(), CreateServiceTypeRequiredSkillInput{SkillID: uuid.New()})
	require.NoError(t, err)
	require.Equal(t, serviceType.ID(), required.ServiceTypeID())

	_, err = service.ListServiceTypeRequiredSkills(context.Background(), actor, otherDealershipID, serviceType.ID())
	require.ErrorContains(t, err, "service_type_not_found")

	repository.createErr = ErrServiceTypeRequiredSkillTaken
	otherSkillID := uuid.New()
	_, err = service.UpdateServiceTypeRequiredSkill(context.Background(), actor, dealershipID, serviceType.ID(), required.ID(), UpdateServiceTypeRequiredSkillInput{SkillID: &otherSkillID})
	require.ErrorContains(t, err, "service_type_required_skill_taken")

	repository.createErr = nil
	repository.deleteErr = nil
	err = service.DeleteServiceTypeRequiredSkill(context.Background(), actor, dealershipID, serviceType.ID(), required.ID())
	require.NoError(t, err)

	repository.deleteErr = errors.New("repository failure")
	err = service.DeleteServiceTypeRequiredSkill(context.Background(), actor, dealershipID, serviceType.ID(), required.ID())
	require.EqualError(t, err, "repository failure")

	nonAdmin := NewService(&requiredSkillRepositoryStub{serviceType: serviceType}, userInfoStub{})
	_, err = nonAdmin.CreateServiceTypeRequiredSkill(context.Background(), actor, dealershipID, serviceType.ID(), CreateServiceTypeRequiredSkillInput{SkillID: uuid.New()})
	require.ErrorContains(t, err, "service_type_required_skill_access_forbidden")
}

type serviceTypeRepositoryStub struct {
	admin       bool
	createErr   error
	deleteErr   error
	serviceType domain.ServiceType
	created     domain.ServiceType
}

func (r *serviceTypeRepositoryStub) Create(context.Context, domain.Dealership) error { return nil }

func (r *serviceTypeRepositoryStub) IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return r.admin, nil
}

func (r *serviceTypeRepositoryStub) CreateServiceType(_ context.Context, serviceType domain.ServiceType) error {
	r.created = serviceType
	return r.createErr
}

func (r *serviceTypeRepositoryStub) GetServiceType(context.Context, uuid.UUID, uuid.UUID) (domain.ServiceType, error) {
	if r.serviceType.ID() == uuid.Nil {
		return domain.ServiceType{}, ErrServiceTypeNotFound
	}
	return r.serviceType, nil
}

func (r *serviceTypeRepositoryStub) ListServiceTypes(context.Context, uuid.UUID) ([]domain.ServiceType, error) {
	return []domain.ServiceType{r.serviceType}, nil
}

func (r *serviceTypeRepositoryStub) UpdateServiceType(_ context.Context, serviceType domain.ServiceType) error {
	r.serviceType = serviceType
	return r.createErr
}

func (r *serviceTypeRepositoryStub) DeleteServiceType(context.Context, uuid.UUID, uuid.UUID, time.Time) error {
	return r.deleteErr
}

func TestServiceTypeAuthorizationValidationUniquenessAndDeletion(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	dealershipID := uuid.New()
	now := time.Date(2026, time.August, 27, 12, 0, 0, 0, time.UTC)
	input := CreateServiceTypeInput{Name: " Oil Change ", DefaultDurationMinutes: 60, MinDurationMinutes: 30, MaxDurationMinutes: 90, IsActive: true}

	tests := []struct {
		name       string
		repository *serviceTypeRepositoryStub
		input      CreateServiceTypeInput
		wantSlug   string
	}{
		{name: "non-admin for dealership is forbidden", repository: &serviceTypeRepositoryStub{}, input: input, wantSlug: "service_type_access_forbidden"},
		{name: "duration order is validated", repository: &serviceTypeRepositoryStub{admin: true}, input: CreateServiceTypeInput{Name: "Oil Change", DefaultDurationMinutes: 30, MinDurationMinutes: 60, MaxDurationMinutes: 90, IsActive: true}, wantSlug: "invalid_service_type"},
		{name: "case insensitive duplicate is conflict", repository: &serviceTypeRepositoryStub{admin: true, createErr: ErrServiceTypeNameTaken}, input: input, wantSlug: "service_type_name_taken"},
		{name: "valid service type is created", repository: &serviceTypeRepositoryStub{admin: true}, input: input},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := NewService(test.repository, userInfoStub{info: client.UserInfo{}})
			service.now = func() time.Time { return now }
			service.newID = func() uuid.UUID { return uuid.MustParse("b4b41eaf-6a1f-45ca-bd89-a1c6a96ff462") }
			created, err := service.CreateServiceType(context.Background(), actor, dealershipID, test.input)
			if test.wantSlug != "" {
				require.Error(t, err)
				require.Contains(t, err.Error(), test.wantSlug)
				return
			}
			require.NoError(t, err)
			require.Equal(t, "Oil Change", created.Name())
			require.Equal(t, dealershipID, test.repository.created.DealershipID())
		})
	}

	service := NewService(&serviceTypeRepositoryStub{admin: true, deleteErr: ErrServiceTypeInUse}, userInfoStub{})
	err := service.DeleteServiceType(context.Background(), actor, dealershipID, uuid.New())
	require.Error(t, err)
	require.Contains(t, err.Error(), "service_type_in_use")
}
