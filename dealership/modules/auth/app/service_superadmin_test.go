package app

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"assessment/modules/auth/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
)

type superadminRepository struct {
	mu          sync.Mutex
	user        domain.User
	created     bool
	createError error
}

func (r *superadminRepository) Create(context.Context, domain.User) error { return nil }
func (r *superadminRepository) CreateSuperadmin(_ context.Context, user domain.User) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.createError != nil {
		return r.createError
	}
	if r.created {
		return ErrAccountExists
	}
	r.created, r.user = true, user
	return nil
}
func (r *superadminRepository) FindByEmail(context.Context, string) (domain.User, error) {
	return domain.User{}, ErrNotFound
}
func (r *superadminRepository) FindSignInUserByEmail(context.Context, string) (AuthenticatedUser, error) {
	return AuthenticatedUser{}, ErrNotFound
}
func (r *superadminRepository) FindByID(context.Context, uuid.UUID) (domain.User, error) {
	return domain.User{}, ErrNotFound
}
func (r *superadminRepository) FindRefreshUserByID(context.Context, uuid.UUID) (AuthenticatedUser, error) {
	return AuthenticatedUser{}, ErrNotFound
}
func (r *superadminRepository) FindRole(context.Context, uuid.UUID) (string, error) {
	return "", ErrNotFound
}
func (r *superadminRepository) UpdateRole(context.Context, uuid.UUID, string, time.Time) error {
	return nil
}
func (r *superadminRepository) Update(context.Context, domain.User) error { return nil }

type superadminTokens struct{}

func (superadminTokens) Issue(domain.User, string) (Tokens, error) { return Tokens{}, nil }
func (superadminTokens) VerifyAccess(string) (Identity, error)     { return Identity{}, nil }
func (superadminTokens) VerifyRefresh(string) (Identity, error)    { return Identity{}, nil }

type superadminHasher struct{}

func (superadminHasher) Hash(password string) (string, error) { return "hash:" + password, nil }
func (superadminHasher) Matches(string, string) bool          { return false }

func TestCreateSuperadminUsesSignUpCredentialRules(t *testing.T) {
	repo := &superadminRepository{}
	service := NewService(repo, superadminTokens{}, superadminHasher{})

	id, err := service.CreateSuperadmin(context.Background(), SignUpInput{Email: " Owner@Example.com ", FullName: "System Owner", Password: "OwnerPass1@"})
	if err != nil || id == uuid.Nil {
		t.Fatalf("CreateSuperadmin() = (%v, %v)", id, err)
	}
	if repo.user.Email() != "owner@example.com" || repo.user.PasswordHash() != "hash:OwnerPass1@" || repo.user.FullName() != "System Owner" {
		t.Fatalf("created user = %#v", repo.user)
	}
}

func TestCreateSuperadminRejectsInvalidInput(t *testing.T) {
	service := NewService(&superadminRepository{}, superadminTokens{}, superadminHasher{})
	_, err := service.CreateSuperadmin(context.Background(), SignUpInput{Email: "owner@example.com", Password: "weak"})
	var clientError common.Error
	if !errors.As(err, &clientError) || clientError.HttpErrorCode != 400 || len(clientError.Details) == 0 {
		t.Fatalf("CreateSuperadmin() error = %#v", err)
	}
}

func TestCreateSuperadminAllowsOnlyOneConcurrentAttempt(t *testing.T) {
	service := NewService(&superadminRepository{}, superadminTokens{}, superadminHasher{})
	input := SignUpInput{Email: "owner@example.com", Password: "OwnerPass1@"}
	results := make(chan error, 2)
	for range 2 {
		go func() { _, err := service.CreateSuperadmin(context.Background(), input); results <- err }()
	}

	var success, conflicts int
	for range 2 {
		err := <-results
		if err == nil {
			success++
			continue
		}
		var clientError common.Error
		if errors.As(err, &clientError) && clientError.ErrorSlug == "account_exists" {
			conflicts++
		}
	}
	if success != 1 || conflicts != 1 {
		t.Fatalf("results = %d successful, %d conflicts", success, conflicts)
	}
}
