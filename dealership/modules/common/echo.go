package common

import (
	"log/slog"

	echo "github.com/labstack/echo/v5"
)

// EchoRouter is the small route-registration surface used by HTTP adapters.
// Both *echo.Echo and *echo.Group implement it.
type EchoRouter interface {
	CONNECT(path string, h echo.HandlerFunc, m ...echo.MiddlewareFunc) echo.RouteInfo
	DELETE(path string, h echo.HandlerFunc, m ...echo.MiddlewareFunc) echo.RouteInfo
	GET(path string, h echo.HandlerFunc, m ...echo.MiddlewareFunc) echo.RouteInfo
	HEAD(path string, h echo.HandlerFunc, m ...echo.MiddlewareFunc) echo.RouteInfo
	OPTIONS(path string, h echo.HandlerFunc, m ...echo.MiddlewareFunc) echo.RouteInfo
	PATCH(path string, h echo.HandlerFunc, m ...echo.MiddlewareFunc) echo.RouteInfo
	POST(path string, h echo.HandlerFunc, m ...echo.MiddlewareFunc) echo.RouteInfo
	PUT(path string, h echo.HandlerFunc, m ...echo.MiddlewareFunc) echo.RouteInfo
	TRACE(path string, h echo.HandlerFunc, m ...echo.MiddlewareFunc) echo.RouteInfo
}

var (
	_ EchoRouter = (*echo.Echo)(nil)
	_ EchoRouter = (*echo.Group)(nil)
)

// EchoConfig contains application-level Echo configuration. Supply an
// IPExtractor that matches the trusted proxy topology when client IP is used
// for logging, authorization, or rate limiting.
type EchoConfig struct {
	Logger           *slog.Logger
	HTTPErrorHandler echo.HTTPErrorHandler
	IPExtractor      echo.IPExtractor
}

// NewEcho creates an Echo v5 server configured with the application's slog
// logger and the API's client-safe error contract. Callers may override the
// handler, but may not accidentally fall back to Echo's error serialization.
func NewEcho(config EchoConfig) *echo.Echo {
	logger := config.Logger
	if logger == nil {
		logger = slog.Default()
	}
	httpErrorHandler := config.HTTPErrorHandler
	if httpErrorHandler == nil {
		httpErrorHandler = EchoErrorHandler
	}

	return echo.NewWithConfig(echo.Config{
		Logger:           logger,
		HTTPErrorHandler: httpErrorHandler,
		IPExtractor:      config.IPExtractor,
	})
}
