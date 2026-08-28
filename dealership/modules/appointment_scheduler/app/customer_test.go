package app

import (
	"context"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/auth/api/module/client"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type customerRepositoryStub struct {
	allowed   bool
	customers map[uuid.UUID]domain.Customer
}

func (r *customerRepositoryStub) Create(context.Context, domain.Dealership) error { return nil }

func (r *customerRepositoryStub) IsActiveCustomerEmployee(context.Context, uuid.UUID) (bool, error) {
	return r.allowed, nil
}

func (r *customerRepositoryStub) CreateCustomer(_ context.Context, customer domain.Customer) (domain.Customer, error) {
	for _, existing := range r.customers {
		if existing.Phone() == customer.Phone() {
			return domain.Customer{}, ErrCustomerPhoneTaken
		}
		if existing.Email() != nil && customer.Email() != nil && *existing.Email() == *customer.Email() {
			return domain.Customer{}, ErrCustomerEmailTaken
		}
	}
	r.customers[customer.ID()] = customer
	return customer, nil
}

func (r *customerRepositoryStub) GetCustomer(_ context.Context, id uuid.UUID) (domain.Customer, error) {
	customer, ok := r.customers[id]
	if !ok {
		return domain.Customer{}, ErrCustomerNotFound
	}
	return customer, nil
}

func (r *customerRepositoryStub) UpdateCustomer(_ context.Context, customer domain.Customer) (domain.Customer, error) {
	if _, ok := r.customers[customer.ID()]; !ok {
		return domain.Customer{}, ErrCustomerNotFound
	}
	for id, existing := range r.customers {
		if id != customer.ID() && existing.Phone() == customer.Phone() {
			return domain.Customer{}, ErrCustomerPhoneTaken
		}
	}
	r.customers[customer.ID()] = customer
	return customer, nil
}

func (r *customerRepositoryStub) GetCustomerByPhone(_ context.Context, phone string) (domain.Customer, error) {
	for _, customer := range r.customers {
		if customer.Phone() == phone {
			return customer, nil
		}
	}
	return domain.Customer{}, ErrCustomerNotFound
}

func (r *customerRepositoryStub) GetCustomerByEmail(_ context.Context, email string) (domain.Customer, error) {
	for _, customer := range r.customers {
		if customer.Email() != nil && *customer.Email() == email {
			return customer, nil
		}
	}
	return domain.Customer{}, ErrCustomerNotFound
}

type customerUserInfoStub struct{}

func (customerUserInfoStub) GetUserInfo(context.Context, uuid.UUID) (client.UserInfo, error) {
	return client.UserInfo{}, nil
}

func (customerUserInfoStub) GetUserInfoByEmail(context.Context, string) (client.UserInfo, error) {
	return client.UserInfo{}, nil
}

func TestCustomerCreateNormalizesIdentifiersAndClearsEmail(t *testing.T) {
	repository := &customerRepositoryStub{allowed: true, customers: map[uuid.UUID]domain.Customer{}}
	service := NewService(repository, customerUserInfoStub{})
	service.now = func() time.Time { return time.Date(2026, 8, 27, 0, 0, 0, 0, time.UTC) }
	actorID := uuid.New()

	customer, err := service.CreateCustomer(context.Background(), actorID, CreateCustomerInput{
		Name: " Jane Doe ", Phone: "+84 901-234-567", Email: customerStringPointer("JANE@Example.COM"),
	})
	require.NoError(t, err)
	require.Equal(t, "Jane Doe", customer.Name())
	require.Equal(t, "+84901234567", customer.Phone())
	require.Equal(t, "jane@example.com", *customer.Email())

	updated, err := service.UpdateCustomer(context.Background(), actorID, customer.ID(), UpdateCustomerInput{EmailPresent: true})
	require.NoError(t, err)
	require.Nil(t, updated.Email())

	_, err = service.CreateCustomer(context.Background(), actorID, CreateCustomerInput{Name: "Duplicate", Phone: "+84901234567"})
	require.ErrorContains(t, err, "customer_phone_already_exists")
	_, err = service.CreateCustomer(context.Background(), actorID, CreateCustomerInput{Name: "Invalid", Phone: "0901234567"})
	require.ErrorContains(t, err, "phone must be a valid E.164")
	_, err = service.GetCustomer(context.Background(), actorID, uuid.New())
	require.ErrorContains(t, err, "customer_not_found")
}

func TestCustomerAuthorizationAndSearchValidation(t *testing.T) {
	for _, role := range []string{"admin", "dealer", "staff"} {
		t.Run(role, func(t *testing.T) {
			repository := &customerRepositoryStub{allowed: true, customers: map[uuid.UUID]domain.Customer{}}
			service := NewService(repository, customerUserInfoStub{})
			_, err := service.SearchCustomers(context.Background(), uuid.New(), customerStringPointer("+84901234567"), nil)
			require.NoError(t, err)
		})
	}

	t.Run("forbidden role", func(t *testing.T) {
		repository := &customerRepositoryStub{allowed: false, customers: map[uuid.UUID]domain.Customer{}}
		service := NewService(repository, customerUserInfoStub{})
		_, err := service.SearchCustomers(context.Background(), uuid.New(), customerStringPointer("+84901234567"), nil)
		require.ErrorContains(t, err, "you are not allowed to manage customers")
	})

	repository := &customerRepositoryStub{allowed: true, customers: map[uuid.UUID]domain.Customer{}}
	service := NewService(repository, customerUserInfoStub{})
	_, err := service.SearchCustomers(context.Background(), uuid.New(), nil, nil)
	require.ErrorContains(t, err, "exactly one of phone or email is required")
}

func customerStringPointer(value string) *string { return &value }
