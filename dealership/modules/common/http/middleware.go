package http

import (
	"log/slog"
	"net/http"
	"time"

	"assessment/modules/common/log"

	echo "github.com/labstack/echo/v5"
	"github.com/labstack/echo/v5/middleware"
	"github.com/lithammer/shortuuid/v3"
	"go.opentelemetry.io/otel/trace"
)

const (
	TestNameHeader          = "TestName"
	CorrelationIDHttpHeader = "Correlation-ID"
)

// useMiddlewares installs timeout, panic recovery, correlation, and request
// logging middleware in the order required by the HTTP boundary.
func useMiddlewares(e *echo.Echo) {
	e.Use(middleware.ContextTimeout(10*time.Second), middleware.Recover(), correlationMiddleware, requestLogMiddleware)
}

// correlationMiddleware propagates a caller-supplied correlation ID or creates
// one and makes it available to both logs and response headers.
func correlationMiddleware(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		req := c.Request()
		correlationID := req.Header.Get(CorrelationIDHttpHeader)
		if correlationID == "" {
			correlationID = shortuuid.New()
		}
		spanContext := trace.SpanContextFromContext(req.Context())
		logger := slog.With("correlation_id", correlationID)
		if spanContext.HasTraceID() {
			logger = logger.With("trace_id", spanContext.TraceID().String(), "span_id", spanContext.SpanID().String())
		}
		if testName := req.Header.Get(TestNameHeader); testName != "" {
			logger = logger.With("test_name", testName)
		}
		ctx := log.ContextWithCorrelationID(log.ToContext(req.Context(), logger), correlationID)
		c.SetRequest(req.WithContext(ctx))
		c.Response().Header().Set(CorrelationIDHttpHeader, correlationID)
		return next(c)
	}
}

// requestLogMiddleware records safe request-completion metadata. It never
// reads or logs request or response bodies, which can contain credentials or PII.
func requestLogMiddleware(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		started := time.Now()
		err := next(c)
		duration := time.Since(started)
		ctx := c.Request().Context()
		spanContext := trace.SpanContextFromContext(ctx)
		logger := log.FromContext(ctx).With(
			"route", c.Path(),
			"status", responseStatus(c.Response(), err),
			"method", c.Request().Method,
			"duration", duration.String(),
		)
		if spanContext.HasTraceID() {
			logger = logger.With("trace_id", spanContext.TraceID().String(), "span_id", spanContext.SpanID().String())
		}
		if err != nil {
			logger = logger.With("error", err)
		}
		logger.Info("Request done")
		return err
	}
}

// responseStatus resolves the status that Echo will send for a response/error pair.
func responseStatus(response http.ResponseWriter, err error) int {
	_, status := echo.ResolveResponseStatus(response, err)
	return status
}
