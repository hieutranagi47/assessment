package app

import (
	"context"
	"errors"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/auth/api/module/client"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type dealershipRepositoryStub struct {
	created                domain.Dealership
	err                    error
	isActiveSchedulerAdmin bool
	authorizationErr       error
}

func (r *dealershipRepositoryStub) Create(_ context.Context, dealership domain.Dealership) error {
	r.created = dealership
	return r.err
}

func (r *dealershipRepositoryStub) IsActiveSchedulerAdmin(context.Context, uuid.UUID) (bool, error) {
	return r.isActiveSchedulerAdmin, r.authorizationErr
}

type userInfoStub struct {
	info client.UserInfo
	err  error
}

func (u userInfoStub) GetUserInfo(context.Context, uuid.UUID) (client.UserInfo, error) {
	return u.info, u.err
}

func (u userInfoStub) GetUserInfoByEmail(context.Context, string) (client.UserInfo, error) {
	return u.info, u.err
}

type userInfoByIDStub struct {
	users    map[uuid.UUID]client.UserInfo
	errs     map[uuid.UUID]error
	targetID uuid.UUID
}

func (u userInfoByIDStub) GetUserInfo(_ context.Context, id uuid.UUID) (client.UserInfo, error) {
	if err := u.errs[id]; err != nil {
		return client.UserInfo{}, err
	}
	info, ok := u.users[id]
	if !ok {
		return client.UserInfo{}, errors.New("user not found")
	}
	return info, nil
}

func (u userInfoByIDStub) GetUserInfoByEmail(_ context.Context, _ string) (client.UserInfo, error) {
	if err := u.errs[u.targetID]; err != nil {
		return client.UserInfo{}, err
	}
	info, ok := u.users[u.targetID]
	if !ok {
		return client.UserInfo{}, errors.New("user not found")
	}
	return info, nil
}

type dealershipAdminRepositoryStub struct {
	dealershipRepositoryStub
	createdAdmin domain.DealershipAdmin
	adminErr     error
}

type dealershipUserRepositoryStub struct {
	dealershipRepositoryStub
	createdUser                         domain.DealershipUser
	userErr                             error
	isActiveAdminForRequestedDealership bool
}

func (r *dealershipUserRepositoryStub) CreateDealershipUser(_ context.Context, user domain.DealershipUser) error {
	if r.userErr != nil {
		return r.userErr
	}
	r.createdUser = user
	return nil
}

func (r *dealershipUserRepositoryStub) IsActiveSchedulerAdminForDealership(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return r.isActiveAdminForRequestedDealership, nil
}

func (r *dealershipAdminRepositoryStub) CreateDealershipAdmin(_ context.Context, admin domain.DealershipAdmin) error {
	if r.adminErr != nil {
		return r.adminErr
	}
	r.createdAdmin = admin
	return nil
}

func TestCreateDealershipAuthorizationAndValidation(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	now := time.Date(2026, time.August, 27, 10, 0, 0, 0, time.UTC)
	input := CreateDealershipInput{Name: " Downtown Motors ", Code: " dtm ", Address: " 1 Main Street ", Timezone: "Asia/Ho_Chi_Minh"}

	tests := []struct {
		name    string
		info    client.UserInfo
		input   CreateDealershipInput
		repoErr error
		wantErr string
	}{
		{name: "superadmin can create", info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "superadmin"}},
		{name: "admin can create", info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}},
		{name: "ordinary user is forbidden", info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "user"}, wantErr: "dealership_create_forbidden"},
		{name: "inactive privileged user is forbidden", info: client.UserInfo{UserID: actor.String(), Status: "disabled", Role: "admin"}, wantErr: "dealership_create_forbidden"},
		{name: "invalid timezone is rejected", info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, input: CreateDealershipInput{Name: input.Name, Code: input.Code, Address: input.Address, Timezone: "Mars/Olympus"}, wantErr: "invalid_dealership"},
		{name: "duplicate code returns conflict", info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, repoErr: ErrDealershipCodeTaken, wantErr: "dealership_code_taken"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			repository := &dealershipRepositoryStub{err: test.repoErr}
			service := NewService(repository, userInfoStub{info: test.info})
			service.now = func() time.Time { return now }
			service.newID = func() uuid.UUID { return uuid.MustParse("b4b41eaf-6a1f-45ca-bd89-a1c6a96ff462") }
			request := input
			if test.input.Name != "" {
				request = test.input
			}

			dealership, err := service.CreateDealership(context.Background(), actor, request)
			if test.wantErr != "" {
				require.Error(t, err)
				require.Contains(t, err.Error(), test.wantErr)
				return
			}
			require.NoError(t, err)
			require.Equal(t, "DTM", dealership.Code())
			require.Equal(t, "Downtown Motors", dealership.Name())
			require.Equal(t, now, dealership.CreatedAt())
		})
	}
}

func TestCreateDealershipRejectsMissingAuthUser(t *testing.T) {
	t.Parallel()
	service := NewService(&dealershipRepositoryStub{}, userInfoStub{err: errors.New("user not found")})
	_, err := service.CreateDealership(context.Background(), uuid.New(), CreateDealershipInput{Name: "Name", Code: "CODE", Address: "Address", Timezone: "UTC"})
	require.Error(t, err)
	require.Contains(t, err.Error(), "dealership_create_forbidden")
}

func TestSearchAuthUserByEmail(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	target := uuid.New()

	tests := []struct {
		name                   string
		actor                  client.UserInfo
		target                 client.UserInfo
		targetErr              error
		isActiveSchedulerAdmin bool
		email                  string
		wantSlug               string
	}{
		{name: "superadmin can search", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "superadmin"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", FullName: "Jane Doe", Status: "active", Role: "user"}, email: " Jane@Example.com "},
		{name: "auth admin can search", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", FullName: "Jane Doe", Status: "active", Role: "user"}, email: "jane@example.com"},
		{name: "scheduler admin can search", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "user"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", FullName: "Jane Doe", Status: "active", Role: "user"}, isActiveSchedulerAdmin: true, email: "jane@example.com"},
		{name: "ordinary user is forbidden", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "user"}, isActiveSchedulerAdmin: false, email: "jane@example.com", wantSlug: "auth_user_search_forbidden"},
		{name: "inactive caller is forbidden", actor: client.UserInfo{UserID: actor.String(), Status: "disabled", Role: "admin"}, email: "jane@example.com", wantSlug: "auth_user_search_forbidden"},
		{name: "empty email is invalid", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, email: " ", wantSlug: "email_required"},
		{name: "missing auth user", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, targetErr: errors.New("not found"), email: "jane@example.com", wantSlug: "auth_user_not_found"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			repository := &dealershipRepositoryStub{isActiveSchedulerAdmin: test.isActiveSchedulerAdmin}
			users := userInfoByIDStub{
				users:    map[uuid.UUID]client.UserInfo{actor: test.actor, target: test.target},
				errs:     map[uuid.UUID]error{target: test.targetErr},
				targetID: target,
			}
			service := NewService(repository, users)

			user, err := service.SearchAuthUserByEmail(context.Background(), actor, test.email)
			if test.wantSlug != "" {
				require.Error(t, err)
				require.Contains(t, err.Error(), test.wantSlug)
				return
			}
			require.NoError(t, err)
			require.Equal(t, target, user.ID)
			require.Equal(t, "jane@example.com", user.Email)
			require.Equal(t, "Jane Doe", user.FullName)
		})
	}
}

func TestCreateDealershipAdmin(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	target := uuid.New()
	dealershipID := uuid.New()
	now := time.Date(2026, time.August, 27, 10, 0, 0, 0, time.UTC)
	input := CreateDealershipAdminInput{
		DealershipID: dealershipID,
		Name:         " Jane Doe ",
		Phone:        pointer(" +84901234567 "),
		Email:        " Jane@Example.com ",
	}

	tests := []struct {
		name       string
		actor      client.UserInfo
		target     client.UserInfo
		targetErr  error
		input      CreateDealershipAdminInput
		repoErr    error
		wantSlug   string
		wantStored bool
	}{
		{name: "superadmin can create", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "superadmin"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", Status: "active"}, input: input, wantStored: true},
		{name: "auth admin can create", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", Status: "active"}, input: input, wantStored: true},
		{name: "unauthorized caller", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "user"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", Status: "active"}, input: input, wantSlug: "dealership_admin_create_forbidden"},
		{name: "inactive caller", actor: client.UserInfo{UserID: actor.String(), Status: "disabled", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", Status: "active"}, input: input, wantSlug: "dealership_admin_create_forbidden"},
		{name: "missing target auth user", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, targetErr: errors.New("not found"), input: input, wantSlug: "auth_user_not_found"},
		{name: "inactive target auth user", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", Status: "disabled"}, input: input, wantSlug: "auth_user_inactive"},
		{name: "missing dealership", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", Status: "active"}, input: input, repoErr: ErrDealershipNotFound, wantSlug: "dealership_not_found"},
		{name: "duplicate auth assignment", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", Status: "active"}, input: input, repoErr: ErrAuthUserAlreadyAssigned, wantSlug: "auth_user_already_assigned"},
		{name: "role assignment failure does not expose a created admin", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "jane@example.com", Status: "active"}, input: input, repoErr: errors.New("role insert failed"), wantSlug: ""},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			repository := &dealershipAdminRepositoryStub{adminErr: test.repoErr}
			users := userInfoByIDStub{
				users:    map[uuid.UUID]client.UserInfo{actor: test.actor, target: test.target},
				errs:     map[uuid.UUID]error{target: test.targetErr},
				targetID: target,
			}
			service := NewService(repository, users)
			service.now = func() time.Time { return now }
			service.newID = func() uuid.UUID { return uuid.MustParse("b4b41eaf-6a1f-45ca-bd89-a1c6a96ff462") }

			admin, err := service.CreateDealershipAdmin(context.Background(), actor, test.input)
			if test.wantSlug != "" {
				require.Error(t, err)
				require.Contains(t, err.Error(), test.wantSlug)
				return
			}
			if test.repoErr != nil {
				require.Error(t, err)
				require.Equal(t, uuid.Nil, admin.ID())
				require.Equal(t, uuid.Nil, repository.createdAdmin.ID())
				return
			}
			require.NoError(t, err)
			require.True(t, test.wantStored)
			require.Equal(t, "Jane Doe", admin.Name())
			require.Equal(t, "+84901234567", *admin.Phone())
			require.Equal(t, "jane@example.com", *admin.Email())
			require.Equal(t, "admin", admin.Role())
			require.Equal(t, now, admin.CreatedAt())
		})
	}
}

func TestCreateDealershipUser(t *testing.T) {
	t.Parallel()
	actor := uuid.New()
	target := uuid.New()
	dealershipID := uuid.New()
	input := CreateDealershipUserInput{DealershipID: dealershipID, Email: "target@example.com", Role: "staff"}

	tests := []struct {
		name       string
		actor      client.UserInfo
		target     client.UserInfo
		repository *dealershipUserRepositoryStub
		input      CreateDealershipUserInput
		wantSlug   string
	}{
		{name: "superadmin", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "superadmin"}, target: client.UserInfo{UserID: target.String(), Email: "target@example.com", FullName: "Target User", Status: "active"}, repository: &dealershipUserRepositoryStub{}, input: input},
		{name: "auth admin", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "target@example.com", FullName: "Target User", Status: "active"}, repository: &dealershipUserRepositoryStub{}, input: input},
		{name: "technician role", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "target@example.com", FullName: "Target User", Status: "active"}, repository: &dealershipUserRepositoryStub{}, input: CreateDealershipUserInput{DealershipID: dealershipID, Email: "target@example.com", Role: "technician"}},
		{name: "same dealership scheduler admin", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "user"}, target: client.UserInfo{UserID: target.String(), Email: "target@example.com", FullName: "Target User", Status: "active"}, repository: &dealershipUserRepositoryStub{isActiveAdminForRequestedDealership: true}, input: input},
		{name: "wrong dealership scheduler admin", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "user"}, target: client.UserInfo{UserID: target.String(), Email: "target@example.com", FullName: "Target User", Status: "active"}, repository: &dealershipUserRepositoryStub{}, input: input, wantSlug: "dealership_user_create_forbidden"},
		{name: "inactive caller", actor: client.UserInfo{UserID: actor.String(), Status: "disabled", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "target@example.com", FullName: "Target User", Status: "active"}, repository: &dealershipUserRepositoryStub{}, input: input, wantSlug: "dealership_user_create_forbidden"},
		{name: "inactive target", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "target@example.com", FullName: "Target User", Status: "disabled"}, repository: &dealershipUserRepositoryStub{}, input: input, wantSlug: "auth_user_inactive"},
		{name: "unsupported role", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, repository: &dealershipUserRepositoryStub{}, input: CreateDealershipUserInput{DealershipID: dealershipID, Email: "target@example.com", Role: "owner"}, wantSlug: "invalid_dealership_user"},
		{name: "invalid email", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, repository: &dealershipUserRepositoryStub{}, input: CreateDealershipUserInput{DealershipID: dealershipID, Email: "not-an-email", Role: "staff"}, wantSlug: "invalid_dealership_user"},
		{name: "duplicate assignment", actor: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}, target: client.UserInfo{UserID: target.String(), Email: "target@example.com", FullName: "Target User", Status: "active"}, repository: &dealershipUserRepositoryStub{userErr: ErrAuthUserAlreadyAssigned}, input: input, wantSlug: "auth_user_already_assigned"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			users := userInfoByIDStub{users: map[uuid.UUID]client.UserInfo{actor: test.actor, target: test.target}, errs: map[uuid.UUID]error{}, targetID: target}
			service := NewService(test.repository, users)
			user, err := service.CreateDealershipUser(context.Background(), actor, test.input)
			if test.wantSlug != "" {
				require.Error(t, err)
				require.Contains(t, err.Error(), test.wantSlug)
				return
			}
			require.NoError(t, err)
			require.Equal(t, "Target User", user.Name())
			require.Equal(t, "target@example.com", user.Email())
			require.Equal(t, test.input.Role, user.Role())
		})
	}
}

func pointer(value string) *string { return &value }
