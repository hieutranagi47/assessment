package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestCustomerLifecycleAndValueIsolation(t *testing.T) {
	now := time.Date(2026, 1, 2, 3, 4, 5, 0, time.FixedZone("ICT", 7*60*60))
	email := "customer@example.com"
	customer, err := NewCustomer(uuid.New(), "Ada", "+84900000000", &email, now)
	require.NoError(t, err)
	require.Equal(t, now, customer.CreatedAt())

	email = "changed@example.com"
	require.Equal(t, "customer@example.com", *customer.Email())
	returnedEmail := customer.Email()
	*returnedEmail = "mutated@example.com"
	require.Equal(t, "customer@example.com", *customer.Email())

	updatedAt := now.Add(time.Hour)
	updated, err := customer.Update("Grace", "+84911111111", nil, updatedAt)
	require.NoError(t, err)
	require.Equal(t, "Grace", updated.Name())
	require.Equal(t, "+84911111111", updated.Phone())
	require.Nil(t, updated.Email())
	require.Equal(t, updatedAt, updated.UpdatedAt())
	require.Equal(t, "Ada", customer.Name())

	restored := RestoreCustomer(customer.ID(), "Lin", "+84922222222", &email, now, updatedAt)
	require.Equal(t, "Lin", restored.Name())
	require.Equal(t, updatedAt, restored.UpdatedAt())
}

func TestCustomerRejectsMissingIdentityOrName(t *testing.T) {
	_, err := NewCustomer(uuid.Nil, "Ada", "", nil, time.Now())
	require.Error(t, err)
	_, err = NewCustomer(uuid.New(), "", "", nil, time.Now())
	require.ErrorIs(t, err, ErrCustomerNameRequired)

	customer := RestoreCustomer(uuid.New(), "Ada", "", nil, time.Now(), time.Now())
	_, err = customer.Update("", "", nil, time.Now())
	require.ErrorIs(t, err, ErrCustomerNameRequired)
}
