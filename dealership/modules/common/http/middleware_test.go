package http

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"assessment/modules/common/log"

	echo "github.com/labstack/echo/v5"
	"github.com/stretchr/testify/require"
)

func TestCorrelationMiddlewarePropagatesProvidedOrGeneratedID(t *testing.T) {
	for _, correlationID := range []string{"caller-id", ""} {
		t.Run(correlationID, func(t *testing.T) {
			e := echo.New()
			request := httptest.NewRequest(http.MethodGet, "/", nil)
			request.Header.Set(CorrelationIDHttpHeader, correlationID)
			response := httptest.NewRecorder()
			ctx := e.NewContext(request, response)
			err := correlationMiddleware(func(c *echo.Context) error {
				id := log.CorrelationIDFromContext(c.Request().Context())
				require.NotEmpty(t, id)
				return c.NoContent(http.StatusNoContent)
			})(ctx)
			require.NoError(t, err)
			if correlationID != "" {
				require.Equal(t, correlationID, response.Header().Get(CorrelationIDHttpHeader))
			}
			require.NotEmpty(t, response.Header().Get(CorrelationIDHttpHeader))
		})
	}
}

func TestResponseStatusUsesEchoResolution(t *testing.T) {
	require.Equal(t, http.StatusNoContent, responseStatus(httptest.NewRecorder(), echo.NewHTTPError(http.StatusNoContent, "")))
	require.Equal(t, http.StatusInternalServerError, responseStatus(httptest.NewRecorder(), assertError{}))
}

type assertError struct{}

func (assertError) Error() string { return "failure" }
