// Package http provides the standard HTTP server boundary for auth modules.
package http

import (
	"log/slog"
	"net/http"

	"assessment/modules/common"

	echo "github.com/labstack/echo/v5"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// NewEcho creates the standard auth HTTP server with health checking,
// request logging, correlation IDs, recovery, and a common error handler.
func NewEcho() *echo.Echo {
	e := common.NewEcho(common.EchoConfig{Logger: slog.Default(), HTTPErrorHandler: common.EchoErrorHandler})
	useMiddlewares(e)
	e.GET("/health", func(c *echo.Context) error { return c.NoContent(http.StatusOK) })
	e.GET("/metrics", echo.WrapHandler(promhttp.Handler()))
	return e
}
