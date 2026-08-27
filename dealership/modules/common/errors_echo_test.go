package common

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	echo "github.com/labstack/echo/v5"
)

func TestHTTPErrorResponseFromCommonError(t *testing.T) {
	err := NewInvalidInputError("invalid_email", "email is invalid").WithDetails([]ErrorDetails{{
		EntityType: "user",
		EntityID:   "42",
		ErrorSlug:  "invalid_email",
		Message:    "must contain @",
	}})

	response, status := httpErrorResponseFromErr(err)
	if status != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", status, http.StatusBadRequest)
	}
	if response.Message != "email is invalid" || response.Slug != "invalid_email" {
		t.Fatalf("response = %#v", response)
	}
	if len(response.Details) != 1 || response.Details[0].EntityID != "42" {
		t.Fatalf("details = %#v", response.Details)
	}
}

func TestHTTPErrorResponseDoesNotExposeInternalError(t *testing.T) {
	response, status := httpErrorResponseFromErr(NewNotFoundError("user_not_found", "user not found").WithInternalError(errors.New("database details")))
	if status != http.StatusNotFound || response.Message != "user not found" || response.Slug != "user_not_found" {
		t.Fatalf("response = %#v, status = %d", response, status)
	}
}

func TestEchoErrorHandlerSerializesContractForUnknownErrors(t *testing.T) {
	e := NewEcho(EchoConfig{})
	e.GET("/failure", func(*echo.Context) error { return errors.New("database password leaked") })

	recorder := httptest.NewRecorder()
	e.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/failure", nil))
	if recorder.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusInternalServerError)
	}

	var response HttpErrorResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if response.Message != "Internal Server Error" || response.Slug != "internal_server_error" || response.Details == nil || len(response.Details) != 0 {
		t.Fatalf("response = %#v", response)
	}
	if got := recorder.Body.String(); strings.Contains(got, "database password leaked") {
		t.Fatalf("response exposes internal error: %s", got)
	}
}

func TestEchoErrorHandlerSerializesAllDetailFields(t *testing.T) {
	e := NewEcho(EchoConfig{})
	e.GET("/failure", func(*echo.Context) error {
		return NewInvalidInputError("invalid_input", "invalid input").WithDetails([]ErrorDetails{{}})
	})

	recorder := httptest.NewRecorder()
	e.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/failure", nil))
	if got, want := recorder.Body.String(), `{"message":"invalid input","slug":"invalid_input","details":[{"entity_type":"","entity_id":"","error_slug":"","message":""}]}`+"\n"; got != want {
		t.Fatalf("response = %s, want %s", got, want)
	}
}
