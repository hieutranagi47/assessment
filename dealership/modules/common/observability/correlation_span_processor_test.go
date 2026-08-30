package observability

import (
	"context"
	"testing"

	"assessment/modules/common/log"

	"github.com/stretchr/testify/require"
	tracesdk "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

func TestCorrelationIDSpanProcessorAddsIDToEveryRequestSpan(t *testing.T) {
	recorder := tracetest.NewSpanRecorder()
	provider := tracesdk.NewTracerProvider(
		tracesdk.WithSpanProcessor(correlationIDSpanProcessor{}),
		tracesdk.WithSpanProcessor(recorder),
	)
	t.Cleanup(func() { require.NoError(t, provider.Shutdown(context.Background())) })

	ctx := log.ContextWithCorrelationID(context.Background(), "manual-flow-123")
	ctx, parent := provider.Tracer("test").Start(ctx, "parent")
	_, child := provider.Tracer("test").Start(ctx, "child")
	child.End()
	parent.End()

	spans := recorder.Ended()
	require.Len(t, spans, 2)
	for _, span := range spans {
		require.Equal(t, "manual-flow-123", spanAttribute(span, correlationIDAttributeKey))
	}
}

func spanAttribute(span tracesdk.ReadOnlySpan, key string) string {
	for _, attribute := range span.Attributes() {
		if string(attribute.Key) == key {
			return attribute.Value.AsString()
		}
	}
	return ""
}
