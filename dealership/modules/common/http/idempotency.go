package http

import (
	"context"
	"net/http"
	"strings"

	echo "github.com/labstack/echo/v5"
)

const IdempotencyIDHeader = "Idempotency-Id"

type IdempotencyStore interface {
	Reserve(context.Context, string) (bool, error)
	Release(context.Context, string) error
}

// IdempotencyMiddleware requires Idempotency-Id for every unsafe API request.
// A key is retained only after a successful response, so callers can retry
// requests that failed before their write transaction completed.
func IdempotencyMiddleware(store IdempotencyStore) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c *echo.Context) error {
			if !isIdempotentWriteMethod(c.Request().Method) {
				return next(c)
			}

			idempotencyID := strings.TrimSpace(c.Request().Header.Get(IdempotencyIDHeader))
			if idempotencyID == "" || len(idempotencyID) > 255 {
				return c.JSON(http.StatusBadRequest, map[string]string{
					"message": "Idempotency-Id header is required and must be at most 255 characters",
					"slug":    "invalid_idempotency_id",
				})
			}

			key := idempotencyStoreKey(c.Request().Method, c.Path(), idempotencyID)
			reserved, err := store.Reserve(c.Request().Context(), key)
			if err != nil {
				return err
			}
			if !reserved {
				return c.JSON(http.StatusConflict, map[string]string{
					"message": "a request with this Idempotency-Id has already been processed",
					"slug":    "idempotency_id_reused",
				})
			}

			err = next(c)
			status := responseStatus(c.Response(), err)
			if err != nil || status < http.StatusOK || status >= http.StatusMultipleChoices {
				releaseErr := store.Release(c.Request().Context(), key)
				if err == nil && releaseErr != nil {
					return releaseErr
				}
			}
			return err
		}
	}
}

func idempotencyStoreKey(method, path, idempotencyID string) string {
	return "idempotency:" + method + ":" + path + ":" + idempotencyID
}

func isIdempotentWriteMethod(method string) bool {
	return method == http.MethodPost || method == http.MethodPut || method == http.MethodPatch
}
