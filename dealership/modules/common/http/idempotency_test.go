package http

import (
	"context"
	"errors"
	stdhttp "net/http"
	"net/http/httptest"
	"testing"

	echo "github.com/labstack/echo/v5"
)

type idempotencyStoreStub struct {
	reserved bool
	err      error
	calls    []string
}

func (s *idempotencyStoreStub) Reserve(_ context.Context, _ string) (bool, error) {
	s.calls = append(s.calls, "reserve")
	if s.err != nil {
		return false, s.err
	}
	return s.reserved, nil
}

func (s *idempotencyStoreStub) Release(_ context.Context, _ string) error {
	s.calls = append(s.calls, "release")
	return s.err
}

func TestIdempotencyMiddleware(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name            string
		method          string
		idempotencyID   string
		reserved        bool
		handlerStatus   int
		wantStatus      int
		wantHandlerCall bool
		wantCommands    int
	}{
		{name: "safe request bypasses idempotency", method: stdhttp.MethodGet, wantStatus: stdhttp.StatusOK, wantHandlerCall: true},
		{name: "write request requires a key", method: stdhttp.MethodPost, wantStatus: stdhttp.StatusBadRequest},
		{name: "new key permits successful write", method: stdhttp.MethodPatch, idempotencyID: "request-1", reserved: true, handlerStatus: stdhttp.StatusNoContent, wantStatus: stdhttp.StatusNoContent, wantHandlerCall: true, wantCommands: 1},
		{name: "reused key is rejected", method: stdhttp.MethodPut, idempotencyID: "request-1", wantStatus: stdhttp.StatusConflict, wantCommands: 1},
		{name: "failed write releases key", method: stdhttp.MethodPost, idempotencyID: "request-1", reserved: true, handlerStatus: stdhttp.StatusBadRequest, wantStatus: stdhttp.StatusBadRequest, wantHandlerCall: true, wantCommands: 2},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			store := &idempotencyStoreStub{reserved: test.reserved}
			e := echo.New()
			called := false
			e.Any("/resources", func(c *echo.Context) error {
				called = true
				status := test.handlerStatus
				if status == 0 {
					status = stdhttp.StatusOK
				}
				return c.NoContent(status)
			}, IdempotencyMiddleware(store))
			request := httptest.NewRequest(test.method, "/resources", nil)
			request.Header.Set(IdempotencyIDHeader, test.idempotencyID)
			response := httptest.NewRecorder()
			e.ServeHTTP(response, request)

			if response.Code != test.wantStatus {
				t.Fatalf("status = %d, want %d", response.Code, test.wantStatus)
			}
			if called != test.wantHandlerCall {
				t.Fatalf("handler called = %t, want %t", called, test.wantHandlerCall)
			}
			if len(store.calls) != test.wantCommands {
				t.Fatalf("store commands = %d, want %d", len(store.calls), test.wantCommands)
			}
		})
	}
}

func TestIdempotencyMiddlewareReturnsStoreError(t *testing.T) {
	store := &idempotencyStoreStub{err: errors.New("database unavailable")}
	e := echo.New()
	e.POST("/resources", func(c *echo.Context) error {
		t.Fatal("handler must not be called")
		return nil
	}, IdempotencyMiddleware(store))

	request := httptest.NewRequest(stdhttp.MethodPost, "/resources", nil)
	request.Header.Set(IdempotencyIDHeader, "request-1")
	response := httptest.NewRecorder()
	e.ServeHTTP(response, request)

	if response.Code != stdhttp.StatusInternalServerError {
		t.Fatalf("status = %d, want %d", response.Code, stdhttp.StatusInternalServerError)
	}
}
