package log

import (
	"bytes"
	"context"
	"log/slog"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestContextHelpersPreserveLoggerAndCorrelationID(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(&bytes.Buffer{}, nil))
	ctx := ToContext(context.Background(), logger)
	ctx = ContextWithCorrelationID(ctx, "request-123")
	require.Same(t, logger, FromContext(ctx))
	require.Equal(t, "request-123", CorrelationIDFromContext(ctx))
	require.NotEmpty(t, CorrelationIDFromContext(context.Background()))
}

func TestHumanHandlerFormatsSortedGroupedAttributesWithoutColour(t *testing.T) {
	var output bytes.Buffer
	handler := NewHandler(&output, &Options{NoColor: true, SortKeys: true, TimeFormat: "15:04:05"})
	logger := slog.New(handler).With("z", "quoted value").WithGroup("request").With("b", 2, "a", true)
	logger.LogAttrs(context.Background(), slog.LevelInfo, "done", slog.Time("time", time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)))

	line := output.String()
	require.Regexp(t, `^\d{2}:\d{2}:\d{2}`, line)
	require.Contains(t, line, " INFO ")
	require.Contains(t, line, "done")
	require.Contains(t, line, "request.a=true")
	require.Contains(t, line, "request.b=2")
	require.Contains(t, line, "z=\"quoted value\"")
	require.NotContains(t, line, "\x1b[")
}

func TestFormatValueAndHandlerLevel(t *testing.T) {
	require.Equal(t, "plain", formatValue(slog.StringValue("plain")))
	require.Equal(t, "\"two words\"", formatValue(slog.StringValue("two words")))
	require.Equal(t, "12", formatValue(slog.Int64Value(12)))
	require.Equal(t, "true", formatValue(slog.BoolValue(true)))

	handler := NewHandler(nil, &Options{HandlerOptions: &slog.HandlerOptions{Level: slog.LevelWarn}})
	require.False(t, handler.Enabled(context.Background(), slog.LevelInfo))
	require.True(t, handler.Enabled(context.Background(), slog.LevelWarn))
}
