package common

import (
	"errors"
	"net/http"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestErrorConstructorsAndDiagnosticFields(t *testing.T) {
	tests := []struct {
		name string
		new  func() Error
		code int
	}{
		{"not found", func() Error { return NewNotFoundError("missing", "record %d", 2) }, http.StatusNotFound},
		{"invalid", func() Error { return NewInvalidInputError("invalid", "bad input") }, http.StatusBadRequest},
		{"conflict", func() Error { return NewConflictError("conflict", "already exists") }, http.StatusConflict},
		{"unauthorized", func() Error { return NewUnauthorizedError("unauthorized", "sign in") }, http.StatusUnauthorized},
		{"forbidden", func() Error { return NewForbiddenError("forbidden", "not allowed") }, http.StatusForbidden},
		{"expired", func() Error { return NewExpiredError("expired", "expired") }, http.StatusGone},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.new()
			require.Equal(t, tt.code, err.HttpErrorCode)
			require.NotEmpty(t, err.ErrorSlug)
		})
	}

	internal := errors.New("database password")
	err := NewConflictError("duplicate", "Email already exists").
		WithInternalError(internal).
		WithDetails([]ErrorDetails{{EntityType: "user", EntityID: "1", ErrorSlug: "duplicate", Message: "already exists"}})
	require.Equal(t, internal, err.InternalError)
	require.Len(t, err.Details, 1)
	require.Contains(t, err.Error(), "Email already exists")
	require.Contains(t, err.Error(), "database password")
}
