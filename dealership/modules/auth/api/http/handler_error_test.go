package http

import (
	"errors"
	"testing"

	"assessment/modules/common"
)

func TestErrorResponsePreservesCommonErrorFields(t *testing.T) {
	err := common.NewInvalidInputError("invalid_email", "email is invalid").WithDetails([]common.ErrorDetails{{
		EntityType: "input",
		EntityID:   "email",
		ErrorSlug:  "invalid_email",
		Message:    "must contain @",
	}}).WithInternalError(errors.New("database diagnostic"))

	response := errorResponse(err, common.NewInvalidInputError("fallback", "fallback"))
	if response.Message != "email is invalid" || response.Slug != "invalid_email" {
		t.Fatalf("response = %#v", response)
	}
	if len(response.Details) != 1 || response.Details[0] != (ErrorDetail{
		EntityType: "input", EntityId: "email", ErrorSlug: "invalid_email", Message: "must contain @",
	}) {
		t.Fatalf("details = %#v", response.Details)
	}
}

func TestErrorResponseUsesClientSafeFallback(t *testing.T) {
	response := errorResponse(errors.New("sensitive database failure"), common.NewInvalidInputError("invalid_request", "invalid request"))
	if response.Message != "invalid request" || response.Slug != "invalid_request" || len(response.Details) != 0 {
		t.Fatalf("response = %#v", response)
	}
}
