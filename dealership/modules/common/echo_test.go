package common

import (
	"io"
	"log/slog"
	"testing"

	echo "github.com/labstack/echo/v5"
	"github.com/stretchr/testify/require"
)

func TestNewEchoUsesConfiguredOrSafeDefaults(t *testing.T) {
	configuredLogger := slog.New(slog.NewTextHandler(io.Discard, nil))
	customHandler := func(*echo.Context, error) {}
	configured := NewEcho(EchoConfig{Logger: configuredLogger, HTTPErrorHandler: customHandler})
	require.Same(t, configuredLogger, configured.Logger)
	require.NotNil(t, configured.HTTPErrorHandler)

	defaults := NewEcho(EchoConfig{})
	require.Same(t, slog.Default(), defaults.Logger)
	require.NotNil(t, defaults.HTTPErrorHandler)
}
