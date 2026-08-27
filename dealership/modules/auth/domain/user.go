package domain

import (
	"errors"
	"net/mail"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrInvalidEmail      = errors.New("a valid email is required")
	ErrInvalidPassword   = errors.New("password is required")
	ErrPasswordPattern   = errors.New("password length greater than 7 and less than 32, atleast one uppercase/lowercase/number/specialcase ('@', '#', '$', '*', '-', '_') letter.")
	ErrInvalidFullName   = errors.New("full name is required")
	ErrPasswordReused    = errors.New("new password must differ from the previous three passwords")
	ErrInvalidUserStatus = errors.New("user status must be active, disabled, or deleted")
	ErrUserNotActive     = errors.New("user is not active")
	ErrInvalidRole       = errors.New("role must be superadmin, admin, or user")
)

type Status string

const (
	RoleSuperadmin = "superadmin"
	RoleAdmin      = "admin"
	RoleUser       = "user"
)

const (
	StatusActive   Status = "active"
	StatusDisabled Status = "disabled"
	StatusDeleted  Status = "deleted"
)

type User struct {
	id                     uuid.UUID
	email, fullName        string
	passwordHash           string
	previousPasswordHashes [2]string
	tokenVersion           int
	status                 Status
	createdAt, updatedAt   time.Time
}

// NewUser creates an active user and establishes the initial refresh-token
// version. Email normalization and required-field validation happen here so
// every newly-created user satisfies the domain invariants.
func NewUser(id uuid.UUID, email, fullName, passwordHash string, now time.Time) (User, error) {
	if id == uuid.Nil {
		return User{}, errors.New("user ID is required")
	}
	email, err := normalizeEmail(email)
	if err != nil {
		return User{}, err
	}
	if strings.TrimSpace(passwordHash) == "" {
		return User{}, ErrInvalidPassword
	}
	now = now.UTC()
	return User{id: id, email: email, fullName: strings.TrimSpace(fullName), passwordHash: passwordHash, tokenVersion: 1, status: StatusActive, createdAt: now, updatedAt: now}, nil
}

// RestoreUser rebuilds a user loaded from storage and validates persisted
// state before allowing it back into the domain.
func RestoreUser(id uuid.UUID, email, fullName, passwordHash string, previous [2]string, tokenVersion int, status Status, createdAt, updatedAt time.Time) (User, error) {
	u, err := NewUser(id, email, fullName, passwordHash, createdAt)
	if err != nil {
		return User{}, err
	}
	if tokenVersion < 1 {
		return User{}, errors.New("token version must be positive")
	}
	if !validStatus(status) {
		return User{}, ErrInvalidUserStatus
	}
	u.previousPasswordHashes, u.tokenVersion, u.status, u.updatedAt = previous, tokenVersion, status, updatedAt.UTC()
	return u, nil
}

// ChangePassword replaces the password and retains the two most recent
// previous hashes.
func (u *User) ChangePassword(newHash string, matches func(string) bool, signOutAll bool, now time.Time) error {
	if strings.TrimSpace(newHash) == "" {
		return ErrInvalidPassword
	}
	if matches(u.passwordHash) || (u.previousPasswordHashes[0] != "" && matches(u.previousPasswordHashes[0])) || (u.previousPasswordHashes[1] != "" && matches(u.previousPasswordHashes[1])) {
		return ErrPasswordReused
	}
	u.previousPasswordHashes[1], u.previousPasswordHashes[0], u.passwordHash = u.previousPasswordHashes[0], u.passwordHash, newHash
	if signOutAll {
		u.tokenVersion++
	}
	u.updatedAt = now.UTC()
	return nil
}

// RevokeRefreshTokens increments the token version, invalidating all refresh
// tokens issued against the previous version.
func (u *User) RevokeRefreshTokens(now time.Time) { u.tokenVersion++; u.updatedAt = now.UTC() }

// UpdateFullName trims and validates a user's display name before recording
// the modification time.
func (u *User) UpdateFullName(fullName string, now time.Time) error {
	fullName = strings.TrimSpace(fullName)
	if fullName == "" {
		return ErrInvalidFullName
	}
	u.fullName, u.updatedAt = fullName, now.UTC()
	return nil
}

// ChangeStatus changes the account lifecycle state after validating the new
// status and updates the modification time.
func (u *User) ChangeStatus(status Status, now time.Time) error {
	if !validStatus(status) {
		return ErrInvalidUserStatus
	}
	u.status, u.updatedAt = status, now.UTC()
	return nil
}

// CanSignIn reports whether the account is currently active.
func (u User) CanSignIn() error {
	if u.status != StatusActive {
		return ErrUserNotActive
	}
	return nil
}

// ID returns the user's immutable identifier.
func (u User) ID() uuid.UUID { return u.id }

// Email returns the normalized email address.
func (u User) Email() string { return u.email }

// FullName returns the user's display name.
func (u User) FullName() string { return u.fullName }

// PasswordHash returns the current password hash for authentication adapters.
func (u User) PasswordHash() string { return u.passwordHash }

// PreviousPasswordHashes returns hashes retained for password-reuse checks.
func (u User) PreviousPasswordHashes() [2]string { return u.previousPasswordHashes }

// TokenVersion returns the refresh-token revocation version.
func (u User) TokenVersion() int { return u.tokenVersion }

// Status returns the account lifecycle state.
func (u User) Status() Status { return u.status }

// CreatedAt returns the creation timestamp.
func (u User) CreatedAt() time.Time { return u.createdAt }

// UpdatedAt returns the last modification timestamp.
func (u User) UpdatedAt() time.Time { return u.updatedAt }

func normalizeEmail(value string) (string, error) {
	value = strings.ToLower(strings.TrimSpace(value))
	address, err := mail.ParseAddress(value)
	if err != nil || address.Address != value {
		return "", ErrInvalidEmail
	}
	return value, nil
}

func validStatus(value Status) bool {
	return value == StatusActive || value == StatusDisabled || value == StatusDeleted
}

// ValidRole reports whether value is one of the roles supported by auth.
func ValidRole(value string) bool {
	return value == RoleSuperadmin || value == RoleAdmin || value == RoleUser
}
