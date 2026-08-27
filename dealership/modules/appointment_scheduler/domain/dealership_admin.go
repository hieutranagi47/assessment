package domain

import (
	"errors"
	"net/mail"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrAuthUserIDRequired   = errors.New("auth user ID is required")
	ErrDealershipIDRequired = errors.New("dealership ID is required")
	ErrAdminNameRequired    = errors.New("dealership admin name is required")
	ErrInvalidAdminPhone    = errors.New("phone must be a valid E.164 number")
	ErrInvalidAdminEmail    = errors.New("email must be a valid email address")
)

var e164Phone = regexp.MustCompile(`^\+[1-9][0-9]{1,14}$`)

// DealershipAdmin is the scheduler-specific user and its sole admin role.
// It deliberately has no technician relationship.
type DealershipAdmin struct {
	id, authUserID, dealershipID uuid.UUID
	name                         string
	phone, email                 *string
	createdAt, updatedAt         time.Time
}

// NewDealershipAdmin validates the scheduler profile before it is persisted.
func NewDealershipAdmin(id, authUserID, dealershipID uuid.UUID, name string, phone, email *string, now time.Time) (DealershipAdmin, error) {
	if id == uuid.Nil {
		return DealershipAdmin{}, errors.New("dealership admin ID is required")
	}
	if authUserID == uuid.Nil {
		return DealershipAdmin{}, ErrAuthUserIDRequired
	}
	if dealershipID == uuid.Nil {
		return DealershipAdmin{}, ErrDealershipIDRequired
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return DealershipAdmin{}, ErrAdminNameRequired
	}
	normalizedPhone, err := normalizeAdminPhone(phone)
	if err != nil {
		return DealershipAdmin{}, err
	}
	normalizedEmail, err := normalizeAdminEmail(email)
	if err != nil {
		return DealershipAdmin{}, err
	}
	now = now.UTC()
	return DealershipAdmin{
		id:           id,
		authUserID:   authUserID,
		dealershipID: dealershipID,
		name:         name,
		phone:        normalizedPhone,
		email:        normalizedEmail,
		createdAt:    now,
		updatedAt:    now,
	}, nil
}

func normalizeAdminPhone(value *string) (*string, error) {
	if value == nil || strings.TrimSpace(*value) == "" {
		return nil, nil
	}
	normalized := strings.TrimSpace(*value)
	if !e164Phone.MatchString(normalized) {
		return nil, ErrInvalidAdminPhone
	}
	return &normalized, nil
}

func normalizeAdminEmail(value *string) (*string, error) {
	if value == nil || strings.TrimSpace(*value) == "" {
		return nil, nil
	}
	normalized := strings.ToLower(strings.TrimSpace(*value))
	address, err := mail.ParseAddress(normalized)
	if err != nil || address.Address != normalized {
		return nil, ErrInvalidAdminEmail
	}
	return &normalized, nil
}

func (a DealershipAdmin) ID() uuid.UUID           { return a.id }
func (a DealershipAdmin) AuthUserID() uuid.UUID   { return a.authUserID }
func (a DealershipAdmin) DealershipID() uuid.UUID { return a.dealershipID }
func (a DealershipAdmin) Name() string            { return a.name }
func (a DealershipAdmin) Phone() *string          { return a.phone }
func (a DealershipAdmin) Email() *string          { return a.email }
func (a DealershipAdmin) IsActive() bool          { return true }
func (a DealershipAdmin) Role() string            { return "admin" }
func (a DealershipAdmin) CreatedAt() time.Time    { return a.createdAt }
func (a DealershipAdmin) UpdatedAt() time.Time    { return a.updatedAt }
