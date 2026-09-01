package http

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"assessment/modules/auth/app"
	"assessment/modules/auth/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
)

type setupRepository struct {
	calls int
	err   error
}

func (r *setupRepository) Create(context.Context, domain.User) error { return nil }
func (r *setupRepository) CreateSuperadmin(_ context.Context, _ domain.User) error {
	r.calls++
	return r.err
}
func (r *setupRepository) FindByEmail(context.Context, string) (domain.User, error) {
	return domain.User{}, app.ErrNotFound
}
func (r *setupRepository) FindSignInUserByEmail(context.Context, string) (app.AuthenticatedUser, error) {
	return app.AuthenticatedUser{}, app.ErrNotFound
}
func (r *setupRepository) FindByID(context.Context, uuid.UUID) (domain.User, error) {
	return domain.User{}, app.ErrNotFound
}
func (r *setupRepository) FindRefreshUserByID(context.Context, uuid.UUID) (app.AuthenticatedUser, error) {
	return app.AuthenticatedUser{}, app.ErrNotFound
}
func (r *setupRepository) FindRole(context.Context, uuid.UUID) (string, error) {
	return "", app.ErrNotFound
}
func (r *setupRepository) UpdateRole(context.Context, uuid.UUID, string, time.Time) error { return nil }
func (r *setupRepository) Update(context.Context, domain.User) error                      { return nil }

type setupTokens struct{}

func (setupTokens) Issue(domain.User, string) (app.Tokens, error) { return app.Tokens{}, nil }
func (setupTokens) VerifyAccess(string) (app.Identity, error)     { return app.Identity{}, nil }
func (setupTokens) VerifyRefresh(string) (app.Identity, error)    { return app.Identity{}, nil }

type setupHasher struct{}

func (setupHasher) Hash(password string) (string, error) { return "hash:" + password, nil }
func (setupHasher) Matches(string, string) bool          { return false }

func newSetupRouter(repo *setupRepository) http.Handler {
	router := common.NewEcho(common.EchoConfig{})
	Register(context.Background(), router, NewHandler(app.NewService(repo, setupTokens{}, setupHasher{})))
	return router
}

func setupRequest(body string) *http.Request {
	req := httptest.NewRequest(http.MethodPost, "/auth/v1/internal/superadmin", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	return req
}

func decodeSetupError(t *testing.T, recorder *httptest.ResponseRecorder) ErrorResponse {
	t.Helper()
	var response ErrorResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	return response
}

func TestCreateSuperadminSerializesSuccessAndStructuredFailures(t *testing.T) {
	t.Run("success", func(t *testing.T) {
		recorder := httptest.NewRecorder()
		newSetupRouter(&setupRepository{}).ServeHTTP(recorder, setupRequest(`{"email":"owner@example.com","password":"OwnerPass1@","full_name":"System Owner"}`))
		if recorder.Code != http.StatusCreated {
			t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
		}
	})
	t.Run("invalid input", func(t *testing.T) {
		recorder := httptest.NewRecorder()
		newSetupRouter(&setupRepository{}).ServeHTTP(recorder, setupRequest(`{"email":"owner@example.com","password":"weak"}`))
		if recorder.Code != http.StatusBadRequest {
			t.Fatalf("status = %d", recorder.Code)
		}
		response := decodeSetupError(t, recorder)
		if response.Details == nil || len(response.Details) != 1 || response.Details[0].EntityId != "password" {
			t.Fatalf("response = %#v", response)
		}
	})
	t.Run("duplicate", func(t *testing.T) {
		recorder := httptest.NewRecorder()
		newSetupRouter(&setupRepository{err: app.ErrAccountExists}).ServeHTTP(recorder, setupRequest(`{"email":"owner@example.com","password":"OwnerPass1@"}`))
		if recorder.Code != http.StatusConflict {
			t.Fatalf("status = %d", recorder.Code)
		}
		response := decodeSetupError(t, recorder)
		if response.Slug != "account_exists" || response.Details == nil || len(response.Details) != 0 {
			t.Fatalf("response = %#v", response)
		}
	})
}

func TestCreateSuperadminUsesSafeFallbackForUnexpectedErrors(t *testing.T) {
	recorder := httptest.NewRecorder()
	newSetupRouter(&setupRepository{err: errors.New("database password leaked")}).ServeHTTP(recorder, setupRequest(`{"email":"owner@example.com","password":"OwnerPass1@"}`))
	if recorder.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	response := decodeSetupError(t, recorder)
	if response.Slug != "internal_server_error" || response.Details == nil || len(response.Details) != 0 || bytes.Contains(recorder.Body.Bytes(), []byte("database password leaked")) {
		t.Fatalf("response = %s", recorder.Body.String())
	}
}
