package http

import (
	"bufio"
	"bytes"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"time"
	"unicode/utf8"

	"assessment/modules/common/log"

	echo "github.com/labstack/echo/v5"
	"github.com/labstack/echo/v5/middleware"
	"github.com/lithammer/shortuuid/v3"
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
		logger := slog.With("correlation_id", correlationID)
		if testName := req.Header.Get(TestNameHeader); testName != "" {
			logger = logger.With("test_name", testName)
		}
		ctx := log.ContextWithCorrelationID(log.ToContext(req.Context(), logger), correlationID)
		c.SetRequest(req.WithContext(ctx))
		c.Response().Header().Set(CorrelationIDHttpHeader, correlationID)
		return next(c)
	}
}

type bodyCapturingWriter struct {
	io.Writer
	http.ResponseWriter
}

// WriteHeader forwards the response status to the underlying writer.
func (w *bodyCapturingWriter) WriteHeader(code int) { w.ResponseWriter.WriteHeader(code) }

// Write captures response bytes for logging while preserving the response writer contract.
func (w *bodyCapturingWriter) Write(b []byte) (int, error) { return w.Writer.Write(b) }

// Flush preserves streaming support when the underlying writer supports it.
func (w *bodyCapturingWriter) Flush() {
	if err := http.NewResponseController(w.ResponseWriter).Flush(); err != nil && !errors.Is(err, http.ErrNotSupported) {
		slog.Warn("response writer flush failed", "error", err)
	}
}

// Hijack preserves WebSocket and raw-connection support.
func (w *bodyCapturingWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	return http.NewResponseController(w.ResponseWriter).Hijack()
}

// Unwrap exposes the original writer to net/http response controllers.
func (w *bodyCapturingWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

// requestLogMiddleware buffers request and response bodies so structured logs
// can include bounded, UTF-8-safe diagnostics.
func requestLogMiddleware(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		var requestBody []byte
		if c.Request().Body != nil {
			requestBody, _ = io.ReadAll(c.Request().Body)
		}
		c.Request().Body = io.NopCloser(bytes.NewBuffer(requestBody))

		responseBody := new(bytes.Buffer)
		response := c.Response()
		c.SetResponse(&bodyCapturingWriter{Writer: io.MultiWriter(response, responseBody), ResponseWriter: response})
		started := time.Now()
		err := next(c)
		duration := time.Since(started)
		ctx := c.Request().Context()
		logger := log.FromContext(ctx).With("URI", c.Request().RequestURI, "status", responseStatus(c.Response(), err), "method", c.Request().Method, "duration", duration.String())
		if err != nil {
			logger = logger.With("error", err)
		}
		logger = logger.With("request_body", truncateBodyForLog(string(requestBody)))
		body := responseBody.String()
		if utf8.ValidString(body) {
			if !log.FromContext(ctx).Enabled(ctx, slog.LevelDebug) {
				body = truncateBodyForLog(body)
			}
			logger = logger.With("response_body", body)
		} else {
			logger = logger.With("response_body", "<binary data>")
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
