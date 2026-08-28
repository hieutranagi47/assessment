package domain

import (
	"errors"
	"net/mail"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrUserNameRequired  = errors.New("dealership user name is required")
	ErrUserEmailRequired = errors.New("dealership user email is required")
	ErrInvalidUserEmail  = errors.New("email must be a valid email address")
	ErrInvalidUserRole   = errors.New("role must be admin, dealer, staff, or technician")
)

// DealershipUser is a login-capable appointment scheduler membership.
type DealershipUser struct {
	id, authUserID, dealershipID uuid.UUID
	name, email                  string
	role                         string
	createdAt, updatedAt         time.Time
}

func NewDealershipUser(id, authUserID, dealershipID uuid.UUID, name, email, role string, now time.Time) (DealershipUser, error) {
	if id == uuid.Nil {
		return DealershipUser{}, errors.New("dealership user ID is required")
	}
	if authUserID == uuid.Nil {
		return DealershipUser{}, ErrAuthUserIDRequired
	}
	if dealershipID == uuid.Nil {
		return DealershipUser{}, ErrDealershipIDRequired
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return DealershipUser{}, ErrUserNameRequired
	}
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return DealershipUser{}, ErrUserEmailRequired
	}
	address, err := mail.ParseAddress(email)
	if err != nil || address.Address != email {
		return DealershipUser{}, ErrInvalidUserEmail
	}
	if role != "admin" && role != "dealer" && role != "staff" && role != "technician" {
		return DealershipUser{}, ErrInvalidUserRole
	}
	now = now.UTC()
	return DealershipUser{id: id, authUserID: authUserID, dealershipID: dealershipID, name: name, email: email, role: role, createdAt: now, updatedAt: now}, nil
}

func (u DealershipUser) ID() uuid.UUID           { return u.id }
func (u DealershipUser) AuthUserID() uuid.UUID   { return u.authUserID }
func (u DealershipUser) DealershipID() uuid.UUID { return u.dealershipID }
func (u DealershipUser) Name() string            { return u.name }
func (u DealershipUser) Email() string           { return u.email }
func (u DealershipUser) Role() string            { return u.role }
func (u DealershipUser) IsActive() bool          { return true }
func (u DealershipUser) CreatedAt() time.Time    { return u.createdAt }
func (u DealershipUser) UpdatedAt() time.Time    { return u.updatedAt }
