package http

import (
	"bytes"
	"context"
	"errors"
	stdhttp "net/http"
	"net/http/httptest"
	"testing"
	"time"

	"assessment/modules/auth/app"
	"assessment/modules/auth/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
)

type authorizationRepository struct {
	findByIDCalls int
	actorRole     string
	target        domain.User
	updatedRole   string
}

func (r *authorizationRepository) Create(context.Context, domain.User, string) error { return nil }
func (r *authorizationRepository) CreateSuperadmin(context.Context, domain.User, string) error {
	return nil
}
func (r *authorizationRepository) FindByEmail(context.Context, string) (domain.User, error) {
	return domain.User{}, app.ErrNotFound
}
func (r *authorizationRepository) FindSignInUserByEmail(context.Context, string) (app.AuthenticatedUser, error) {
	return app.AuthenticatedUser{}, app.ErrNotFound
}
func (r *authorizationRepository) FindByID(_ context.Context, id uuid.UUID) (domain.User, error) {
	r.findByIDCalls++
	if id == r.target.ID() {
		return r.target, nil
	}
	return domain.User{}, app.ErrNotFound
}
func (r *authorizationRepository) FindRefreshUserByID(context.Context, uuid.UUID) (app.AuthenticatedUser, error) {
	return app.AuthenticatedUser{}, app.ErrNotFound
}
func (r *authorizationRepository) FindRole(context.Context, uuid.UUID) (string, error) {
	if r.actorRole != "" {
		return r.actorRole, nil
	}
	return "", app.ErrNotFound
}
func (r *authorizationRepository) UpdateRole(_ context.Context, _ uuid.UUID, role string, _ time.Time) error {
	r.updatedRole = role
	return nil
}
func (r *authorizationRepository) Update(context.Context, domain.User) error { return nil }
func (r *authorizationRepository) UpdatePassword(context.Context, domain.User, string, string) error {
	return nil
}
func (r *authorizationRepository) StoreDeliveryEmail(context.Context, uuid.UUID, string) error {
	return nil
}

type authorizationTokens struct {
	identity app.Identity
	err      error
}

func (t authorizationTokens) Issue(domain.User, string) (app.Tokens, error) { return app.Tokens{}, nil }
func (t authorizationTokens) VerifyAccess(string) (app.Identity, error) {
	return t.identity, t.err
}
func (t authorizationTokens) VerifyRefresh(string) (app.Identity, error) {
	return app.Identity{}, errors.New("not implemented")
}

func newAuthorizationRouter(repo *authorizationRepository, tokens authorizationTokens) stdhttp.Handler {
	router := common.NewEcho(common.EchoConfig{})
	Register(context.Background(), router, NewHandler(app.NewService(repo, tokens, setupHasher{})))
	return router
}

func TestUserSelfUpdateEndpointsRequireIdentity(t *testing.T) {
	operations := []struct {
		method string
		path   string
		body   string
	}{
		{stdhttp.MethodPut, "/auth/v1/users/4a2a5e92-66d8-4d1d-bc61-693c404cd3d8/password", `{"password":"CurrentPass1@","new_password":"NextPass1@"}`},
		{stdhttp.MethodPatch, "/auth/v1/users/4a2a5e92-66d8-4d1d-bc61-693c404cd3d8/full-name", `{"full_name":"Updated User"}`},
		{stdhttp.MethodPatch, "/auth/v1/users/4a2a5e92-66d8-4d1d-bc61-693c404cd3d8/status", `{"status":"disabled"}`},
	}

	for _, operation := range operations {
		t.Run(operation.path, func(t *testing.T) {
			repo := &authorizationRepository{}
			recorder := httptest.NewRecorder()
			req := httptest.NewRequest(operation.method, operation.path, bytes.NewBufferString(operation.body))
			req.Header.Set("Content-Type", "application/json")
			newAuthorizationRouter(repo, authorizationTokens{err: errors.New("invalid token")}).ServeHTTP(recorder, req)

			if recorder.Code != stdhttp.StatusUnauthorized {
				t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
			}
			if repo.findByIDCalls != 0 {
				t.Fatalf("repository queried without an authenticated identity")
			}
		})
	}
}

func TestUserSelfUpdateEndpointsRejectAnotherUser(t *testing.T) {
	target := uuid.MustParse("4a2a5e92-66d8-4d1d-bc61-693c404cd3d8")
	actor := uuid.MustParse("796c4a53-bd4f-4450-a203-c6706db4f999")
	operations := []struct {
		method string
		path   string
		body   string
	}{
		{stdhttp.MethodPut, "/auth/v1/users/" + target.String() + "/password", `{"password":"CurrentPass1@","new_password":"NextPass1@"}`},
		{stdhttp.MethodPatch, "/auth/v1/users/" + target.String() + "/full-name", `{"full_name":"Updated User"}`},
		{stdhttp.MethodPatch, "/auth/v1/users/" + target.String() + "/status", `{"status":"disabled"}`},
	}

	for _, operation := range operations {
		t.Run(operation.path, func(t *testing.T) {
			repo := &authorizationRepository{}
			recorder := httptest.NewRecorder()
			req := httptest.NewRequest(operation.method, operation.path, bytes.NewBufferString(operation.body))
			req.Header.Set("Authorization", "Bearer valid-access-token")
			req.Header.Set("Content-Type", "application/json")
			newAuthorizationRouter(repo, authorizationTokens{identity: app.Identity{UserID: actor}}).ServeHTTP(recorder, req)

			if recorder.Code != stdhttp.StatusForbidden {
				t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
			}
			if repo.findByIDCalls != 0 {
				t.Fatalf("repository queried before denying a cross-user update")
			}
		})
	}
}

func TestUpdateUserRoleAuthorization(t *testing.T) {
	actor, target := uuid.New(), uuid.New()
	targetUser, err := domain.NewUser(target, "target@example.com", "Target", "hash", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	request := func() *stdhttp.Request {
		req := httptest.NewRequest(stdhttp.MethodPatch, "/auth/v1/users/"+target.String()+"/role", bytes.NewBufferString(`{"role":"admin"}`))
		req.Header.Set("Authorization", "Bearer valid-access-token")
		req.Header.Set("Content-Type", "application/json")
		return req
	}

	t.Run("superadmin can assign a role", func(t *testing.T) {
		repo := &authorizationRepository{actorRole: domain.RoleSuperadmin, target: targetUser}
		recorder := httptest.NewRecorder()
		newAuthorizationRouter(repo, authorizationTokens{identity: app.Identity{UserID: actor}}).ServeHTTP(recorder, request())
		if recorder.Code != stdhttp.StatusNoContent || repo.updatedRole != domain.RoleAdmin {
			t.Fatalf("status = %d, role = %q", recorder.Code, repo.updatedRole)
		}
	})
	t.Run("admin is forbidden", func(t *testing.T) {
		repo := &authorizationRepository{actorRole: domain.RoleAdmin, target: targetUser}
		recorder := httptest.NewRecorder()
		newAuthorizationRouter(repo, authorizationTokens{identity: app.Identity{UserID: actor}}).ServeHTTP(recorder, request())
		if recorder.Code != stdhttp.StatusForbidden || repo.updatedRole != "" {
			t.Fatalf("status = %d, role = %q", recorder.Code, repo.updatedRole)
		}
	})
	t.Run("superadmin cannot update itself", func(t *testing.T) {
		repo := &authorizationRepository{actorRole: domain.RoleSuperadmin, target: targetUser}
		recorder := httptest.NewRecorder()
		newAuthorizationRouter(repo, authorizationTokens{identity: app.Identity{UserID: target}}).ServeHTTP(recorder, request())
		if recorder.Code != stdhttp.StatusForbidden || repo.updatedRole != "" {
			t.Fatalf("status = %d, role = %q", recorder.Code, repo.updatedRole)
		}
	})
}
