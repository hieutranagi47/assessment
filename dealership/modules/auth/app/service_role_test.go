package app

import (
	"context"
	"strings"
	"testing"
	"time"

	"assessment/modules/auth/domain"

	"github.com/google/uuid"
)

type roleRepository struct {
	actorRole string
	target    domain.User
	emailUser domain.User
	updatedID uuid.UUID
	updatedTo string
	calls     int
}

func (r *roleRepository) Create(context.Context, domain.User, string) error           { return nil }
func (r *roleRepository) CreateSuperadmin(context.Context, domain.User, string) error { return nil }

func (r *roleRepository) FindByEmail(_ context.Context, email string) (domain.User, error) {
	if r.emailUser.ID() != uuid.Nil && strings.EqualFold(strings.TrimSpace(email), r.emailUser.Email()) {
		return r.emailUser, nil
	}
	return domain.User{}, ErrNotFound
}
func (r *roleRepository) FindSignInUserByEmail(ctx context.Context, email string) (AuthenticatedUser, error) {
	user, err := r.FindByEmail(ctx, email)
	return AuthenticatedUser{User: user, Role: r.actorRole}, err
}
func (r *roleRepository) FindByID(_ context.Context, id uuid.UUID) (domain.User, error) {
	if id != r.target.ID() {
		return domain.User{}, ErrNotFound
	}
	return r.target, nil
}
func (r *roleRepository) FindRefreshUserByID(ctx context.Context, id uuid.UUID) (AuthenticatedUser, error) {
	user, err := r.FindByID(ctx, id)
	return AuthenticatedUser{User: user, Role: r.actorRole}, err
}

func TestUserInfoByEmailNormalizesTheLookupAndReturnsCurrentRole(t *testing.T) {
	user, err := domain.NewUser(uuid.New(), "user@example.com", "User", "hash", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	repository := &roleRepository{
		actorRole: domain.RoleAdmin,
		emailUser: user,
	}

	info, err := NewService(repository, superadminTokens{}, superadminHasher{}).UserInfoByEmail(context.Background(), " User@Example.com ")
	if err != nil {
		t.Fatalf("UserInfoByEmail() error = %v", err)
	}
	if info.UserID != user.ID().String() || info.Email != user.Email() || info.Role != domain.RoleAdmin {
		t.Fatalf("UserInfoByEmail() = %#v", info)
	}
}
func (r *roleRepository) FindRole(context.Context, uuid.UUID) (string, error) {
	return r.actorRole, nil
}
func (r *roleRepository) UpdateRole(_ context.Context, id uuid.UUID, role string, _ time.Time) error {
	r.updatedID, r.updatedTo = id, role
	r.calls++
	return nil
}
func (r *roleRepository) Update(context.Context, domain.User) error { return nil }
func (r *roleRepository) UpdatePassword(context.Context, domain.User, string, string) error {
	return nil
}
func (r *roleRepository) StoreDeliveryEmail(context.Context, uuid.UUID, string) error { return nil }

func TestUpdateRoleOnlyAllowsSuperadminToChangeAnotherAccount(t *testing.T) {
	actor, target := uuid.New(), uuid.New()
	user, err := domain.NewUser(target, "user@example.com", "User", "hash", time.Now())
	if err != nil {
		t.Fatal(err)
	}

	t.Run("superadmin grants any valid role", func(t *testing.T) {
		repo := &roleRepository{actorRole: domain.RoleSuperadmin, target: user}
		service := NewService(repo, superadminTokens{}, superadminHasher{})
		if err := service.UpdateRole(context.Background(), actor, target, domain.RoleAdmin); err != nil {
			t.Fatalf("UpdateRole() error = %v", err)
		}
		if repo.calls != 1 || repo.updatedID != target || repo.updatedTo != domain.RoleAdmin {
			t.Fatalf("update = (%v, %q, %d)", repo.updatedID, repo.updatedTo, repo.calls)
		}
	})

	for _, actorRole := range []string{domain.RoleAdmin, domain.RoleUser} {
		t.Run(actorRole+" is forbidden", func(t *testing.T) {
			repo := &roleRepository{actorRole: actorRole, target: user}
			err := NewService(repo, superadminTokens{}, superadminHasher{}).UpdateRole(context.Background(), actor, target, domain.RoleUser)
			if err != ErrForbidden || repo.calls != 0 {
				t.Fatalf("UpdateRole() = %v, calls = %d", err, repo.calls)
			}
		})
	}

	t.Run("superadmin cannot change own role", func(t *testing.T) {
		repo := &roleRepository{actorRole: domain.RoleSuperadmin, target: user}
		err := NewService(repo, superadminTokens{}, superadminHasher{}).UpdateRole(context.Background(), target, target, domain.RoleAdmin)
		if err != ErrForbidden || repo.calls != 0 {
			t.Fatalf("UpdateRole() = %v, calls = %d", err, repo.calls)
		}
	})

	t.Run("invalid role is rejected", func(t *testing.T) {
		repo := &roleRepository{actorRole: domain.RoleSuperadmin, target: user}
		err := NewService(repo, superadminTokens{}, superadminHasher{}).UpdateRole(context.Background(), actor, target, "owner")
		if err != domain.ErrInvalidRole || repo.calls != 0 {
			t.Fatalf("UpdateRole() = %v, calls = %d", err, repo.calls)
		}
	})
}
