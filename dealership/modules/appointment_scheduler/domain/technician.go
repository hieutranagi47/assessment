package domain

import (
	"errors"
	"net/mail"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrTechnicianIDRequired     = errors.New("technician ID is required")
	ErrTechnicianUserIDRequired = errors.New("technician user ID is required")
	ErrTechnicianNameRequired   = errors.New("technician name is required")
	ErrTechnicianPhoneInvalid   = errors.New("technician phone must use E.164 format")
	ErrTechnicianEmailInvalid   = errors.New("technician email is invalid")
)

// Technician is a dealership employee with technical qualifications. Its user
// identity is deliberately immutable: a technician can be edited but never
// repointed.
type Technician struct {
	id, userID           uuid.UUID
	name, phone          string
	email                *string
	isActive             bool
	createdAt, updatedAt time.Time
}

func NewTechnician(id, userID uuid.UUID, name, phone string, email *string, isActive bool, now time.Time) (Technician, error) {
	if id == uuid.Nil {
		return Technician{}, ErrTechnicianIDRequired
	}
	if userID == uuid.Nil {
		return Technician{}, ErrTechnicianUserIDRequired
	}
	name, phone, email, err := validateTechnicianDetails(name, phone, email)
	if err != nil {
		return Technician{}, err
	}
	now = now.UTC()
	return Technician{id: id, userID: userID, name: name, phone: phone, email: email, isActive: isActive, createdAt: now, updatedAt: now}, nil
}

func RehydrateTechnician(id, userID uuid.UUID, name, phone string, email *string, isActive bool, createdAt, updatedAt time.Time) (Technician, error) {
	technician, err := NewTechnician(id, userID, name, phone, email, isActive, createdAt)
	if err != nil {
		return Technician{}, err
	}
	technician.updatedAt = updatedAt.UTC()
	return technician, nil
}

func (t Technician) Update(name, phone string, email *string, isActive bool, now time.Time) (Technician, error) {
	name, phone, email, err := validateTechnicianDetails(name, phone, email)
	if err != nil {
		return Technician{}, err
	}
	t.name, t.phone, t.email, t.isActive, t.updatedAt = name, phone, email, isActive, now.UTC()
	return t, nil
}

func validateTechnicianDetails(name, phone string, email *string) (string, string, *string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", "", nil, ErrTechnicianNameRequired
	}
	phone = normalizePhone(phone)
	if !isE164(phone) {
		return "", "", nil, ErrTechnicianPhoneInvalid
	}
	if email == nil {
		return name, phone, nil, nil
	}
	normalizedEmail := strings.ToLower(strings.TrimSpace(*email))
	if normalizedEmail == "" {
		return "", "", nil, ErrTechnicianEmailInvalid
	}
	parsed, err := mail.ParseAddress(normalizedEmail)
	if err != nil || parsed.Address != normalizedEmail {
		return "", "", nil, ErrTechnicianEmailInvalid
	}
	return name, phone, &normalizedEmail, nil
}

func normalizePhone(value string) string {
	value = strings.TrimSpace(value)
	value = strings.NewReplacer(" ", "", "-", "", "(", "", ")", "", ".", "").Replace(value)
	if strings.HasPrefix(value, "00") {
		value = "+" + value[2:]
	}
	return value
}

func isE164(value string) bool {
	if len(value) < 9 || len(value) > 16 || value[0] != '+' || value[1] == '0' {
		return false
	}
	for _, character := range value[1:] {
		if character < '0' || character > '9' {
			return false
		}
	}
	return true
}

func (t Technician) ID() uuid.UUID        { return t.id }
func (t Technician) UserID() uuid.UUID    { return t.userID }
func (t Technician) Name() string         { return t.name }
func (t Technician) Phone() string        { return t.phone }
func (t Technician) Email() *string       { return copyString(t.email) }
func (t Technician) IsActive() bool       { return t.isActive }
func (t Technician) CreatedAt() time.Time { return t.createdAt }
func (t Technician) UpdatedAt() time.Time { return t.updatedAt }
