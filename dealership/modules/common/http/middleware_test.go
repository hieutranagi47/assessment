package http

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"assessment/modules/common/log"

	echo "github.com/labstack/echo/v5"
	"github.com/stretchr/testify/require"
	tracesdk "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
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

func TestCorrelationMiddlewareAddsIDToActiveTrace(t *testing.T) {
	recorder := tracetest.NewSpanRecorder()
	provider := tracesdk.NewTracerProvider(tracesdk.WithSpanProcessor(recorder))
	t.Cleanup(func() { require.NoError(t, provider.Shutdown(context.Background())) })

	requestContext, span := provider.Tracer("test").Start(context.Background(), "request")
	request := httptest.NewRequest(http.MethodGet, "/", nil).WithContext(requestContext)
	request.Header.Set(CorrelationIDHttpHeader, "caller-id")
	response := httptest.NewRecorder()
	server := echo.New()

	err := correlationMiddleware(func(c *echo.Context) error {
		return c.NoContent(http.StatusNoContent)
	})(server.NewContext(request, response))
	require.NoError(t, err)
	span.End()

	spans := recorder.Ended()
	require.Len(t, spans, 1)
	require.Equal(t, "caller-id", spanAttribute(spans[0], "correlation_id"))
}

func TestResponseStatusUsesEchoResolution(t *testing.T) {
	require.Equal(t, http.StatusNoContent, responseStatus(httptest.NewRecorder(), echo.NewHTTPError(http.StatusNoContent, "")))
	require.Equal(t, http.StatusInternalServerError, responseStatus(httptest.NewRecorder(), assertError{}))
}

type assertError struct{}

func (assertError) Error() string { return "failure" }

func spanAttribute(span tracesdk.ReadOnlySpan, key string) string {
	for _, attribute := range span.Attributes() {
		if string(attribute.Key) == key {
			return attribute.Value.AsString()
		}
	}
	return ""
}
