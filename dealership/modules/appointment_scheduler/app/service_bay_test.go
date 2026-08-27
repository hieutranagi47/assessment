package app

import (
	"context"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/domain"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type serviceBayRepositoryStub struct {
	admin      bool
	createErr  error
	deleteErr  error
	serviceBay domain.ServiceBay
}

func (r *serviceBayRepositoryStub) Create(context.Context, domain.Dealership) error { return nil }

func (r *serviceBayRepositoryStub) IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return r.admin, nil
}

func (r *serviceBayRepositoryStub) CreateServiceBay(_ context.Context, serviceBay domain.ServiceBay) error {
	r.serviceBay = serviceBay
	return r.createErr
}

func (r *serviceBayRepositoryStub) GetServiceBay(context.Context, uuid.UUID, uuid.UUID) (domain.ServiceBay, error) {
	if r.serviceBay.ID() == uuid.Nil {
		return domain.ServiceBay{}, ErrServiceBayNotFound
	}
	return r.serviceBay, nil
}

func (r *serviceBayRepositoryStub) ListServiceBays(context.Context, uuid.UUID, *bool, int, int) ([]domain.ServiceBay, error) {
	return []domain.ServiceBay{r.serviceBay}, nil
}

func (r *serviceBayRepositoryStub) UpdateServiceBay(_ context.Context, serviceBay domain.ServiceBay) error {
	r.serviceBay = serviceBay
	return r.createErr
}

func (r *serviceBayRepositoryStub) DeleteServiceBay(context.Context, uuid.UUID, uuid.UUID, time.Time) error {
	return r.deleteErr
}

func TestServiceBayAuthorizationValidationUniquenessAndDeleteConflict(t *testing.T) {
	actor := uuid.New()
	dealershipID := uuid.New()
	input := CreateServiceBayInput{Code: " Bay-01 ", Name: " Main bay ", IsActive: true}

	tests := []struct {
		name       string
		repository *serviceBayRepositoryStub
		input      CreateServiceBayInput
		wantSlug   string
	}{
		{name: "only dealership admins may create", repository: &serviceBayRepositoryStub{}, input: input, wantSlug: "service_bay_access_forbidden"},
		{name: "code is required after trimming", repository: &serviceBayRepositoryStub{admin: true}, input: CreateServiceBayInput{Code: " ", Name: "Main", IsActive: true}, wantSlug: "invalid_service_bay"},
		{name: "name is required after trimming", repository: &serviceBayRepositoryStub{admin: true}, input: CreateServiceBayInput{Code: "B-1", Name: " ", IsActive: true}, wantSlug: "invalid_service_bay"},
		{name: "case insensitive duplicate is a conflict", repository: &serviceBayRepositoryStub{admin: true, createErr: ErrServiceBayCodeTaken}, input: input, wantSlug: "service_bay_code_taken"},
		{name: "valid service bay is normalized", repository: &serviceBayRepositoryStub{admin: true}, input: input},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			service := NewService(test.repository, userInfoStub{})
			service.newID = func() uuid.UUID { return uuid.MustParse("f06d6d2a-d0a2-4a7e-9941-27a5fe142176") }
			created, err := service.CreateServiceBay(context.Background(), actor, dealershipID, test.input)
			if test.wantSlug != "" {
				require.ErrorContains(t, err, test.wantSlug)
				return
			}
			require.NoError(t, err)
			require.Equal(t, "Bay-01", created.Code())
			require.Equal(t, "Main bay", created.Name())
		})
	}

	service := NewService(&serviceBayRepositoryStub{admin: true, deleteErr: ErrServiceBayInUse}, userInfoStub{})
	err := service.DeleteServiceBay(context.Background(), actor, dealershipID, uuid.New())
	require.ErrorContains(t, err, "service_bay_in_use")
}

func TestServiceBayPaginationIsValidated(t *testing.T) {
	service := NewService(&serviceBayRepositoryStub{admin: true}, userInfoStub{})
	_, err := service.ListServiceBays(context.Background(), uuid.New(), uuid.New(), nil, 101, 0)
	require.ErrorContains(t, err, "invalid_pagination")
}
