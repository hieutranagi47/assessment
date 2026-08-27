package common

import (
	"errors"
	"net/http"
	"strings"

	"assessment/modules/common/log"

	echo "github.com/labstack/echo/v5"
)

// EchoErrorHandler is the single HTTP boundary for translating application
// errors into client-safe JSON responses.
// EchoErrorHandler converts internal errors into a stable client-safe JSON
// response and avoids writing a second response after commitment.
func EchoErrorHandler(c *echo.Context, err error) {
	if response, unwrapErr := echo.UnwrapResponse(c.Response()); unwrapErr == nil && response.Committed {
		return
	}

	response, status := httpErrorResponseFromErr(err)
	log.FromContext(c.Request().Context()).With("err", err).Error("Handling HTTP error")
	if err := c.JSON(status, response); err != nil {
		log.FromContext(c.Request().Context()).With("error", err).Error("Failed to send error response")
	}
}

type HttpErrorResponse struct {
	Message string            `json:"message"`
	Slug    string            `json:"slug"`
	Details []HttpErrorDetail `json:"details"`
}

type HttpErrorDetail struct {
	EntityType string `json:"entity_type"`
	EntityID   string `json:"entity_id"`
	ErrorSlug  string `json:"error_slug"`
	Message    string `json:"message"`
}

// httpErrorResponseFromErr maps Echo and common errors without exposing their
// internal causes to clients.
func httpErrorResponseFromErr(err error) (HttpErrorResponse, int) {
	message, status := "Internal Server Error", http.StatusInternalServerError
	var echoErr *echo.HTTPError
	if errors.As(err, &echoErr) {
		status, message = echoErr.Code, http.StatusText(echoErr.Code)
	}
	slug := strings.ToLower(strings.ReplaceAll(message, " ", "_"))

	var commonErr Error
	if errors.As(err, &commonErr) {
		if commonErr.PublicError != "" {
			message = commonErr.PublicError
		}
		if commonErr.ErrorSlug != "" {
			slug = commonErr.ErrorSlug
		}
		if commonErr.HttpErrorCode != 0 {
			status = commonErr.HttpErrorCode
		}
	}

	details := make([]HttpErrorDetail, 0, len(commonErr.Details))
	for _, detail := range commonErr.Details {
		details = append(details, HttpErrorDetail(detail))
	}
	return HttpErrorResponse{Message: message, Slug: slug, Details: details}, status
}
