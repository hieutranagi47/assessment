package domain

import (
	"errors"
	"time"

	"github.com/google/uuid"
)

var ErrCustomerNameRequired = errors.New("customer name is required")

// Customer is a global customer record. It deliberately carries no dealership
// ownership because the current database schema does not model that boundary.
type Customer struct {
	id        uuid.UUID
	name      string
	phone     string
	email     *string
	createdAt time.Time
	updatedAt time.Time
}

func NewCustomer(id uuid.UUID, name, phone string, email *string, now time.Time) (Customer, error) {
	if id == uuid.Nil {
		return Customer{}, errors.New("customer ID is required")
	}
	if name == "" {
		return Customer{}, ErrCustomerNameRequired
	}
	return Customer{id: id, name: name, phone: phone, email: copyString(email), createdAt: now, updatedAt: now}, nil
}

func RestoreCustomer(id uuid.UUID, name, phone string, email *string, createdAt, updatedAt time.Time) Customer {
	return Customer{id: id, name: name, phone: phone, email: copyString(email), createdAt: createdAt, updatedAt: updatedAt}
}

func (c Customer) ID() uuid.UUID        { return c.id }
func (c Customer) Name() string         { return c.name }
func (c Customer) Phone() string        { return c.phone }
func (c Customer) Email() *string       { return copyString(c.email) }
func (c Customer) CreatedAt() time.Time { return c.createdAt }
func (c Customer) UpdatedAt() time.Time { return c.updatedAt }

func (c Customer) Update(name, phone string, email *string, now time.Time) (Customer, error) {
	if name == "" {
		return Customer{}, ErrCustomerNameRequired
	}
	c.name = name
	c.phone = phone
	c.email = copyString(email)
	c.updatedAt = now
	return c, nil
}

func copyString(value *string) *string {
	if value == nil {
		return nil
	}
	copy := *value
	return &copy
}
