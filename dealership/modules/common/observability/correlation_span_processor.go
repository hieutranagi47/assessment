package observability

import (
	"context"

	"assessment/modules/common/log"

	"go.opentelemetry.io/otel/attribute"
	tracesdk "go.opentelemetry.io/otel/sdk/trace"
)

const correlationIDAttributeKey = "correlation_id"

// correlationIDSpanProcessor copies the request correlation ID from context to
// every span created within that request. OpenTelemetry propagates span context
// automatically, but application-specific context values need this explicit
// bridge to become searchable span attributes.
type correlationIDSpanProcessor struct{}

func (correlationIDSpanProcessor) OnStart(ctx context.Context, span tracesdk.ReadWriteSpan) {
	if correlationID, ok := log.CorrelationID(ctx); ok {
		span.SetAttributes(attribute.String(correlationIDAttributeKey, correlationID))
	}
}

func (correlationIDSpanProcessor) OnEnd(tracesdk.ReadOnlySpan) {}

func (correlationIDSpanProcessor) Shutdown(context.Context) error { return nil }

func (correlationIDSpanProcessor) ForceFlush(context.Context) error { return nil }
