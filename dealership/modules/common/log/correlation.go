package log

import (
	"context"

	"github.com/lithammer/shortuuid/v3"
)

// ContextWithCorrelationID stores a request correlation ID in context.
func ContextWithCorrelationID(ctx context.Context, correlationID string) context.Context {
	return context.WithValue(ctx, correlationIDKey, correlationID)
}

// CorrelationID returns the correlation ID when the HTTP boundary added one to
// the context. It does not generate a fallback because tracing must not create
// a new ID for a span that is not part of a request flow.
func CorrelationID(ctx context.Context) (string, bool) {
	correlationID, ok := ctx.Value(correlationIDKey).(string)
	return correlationID, ok && correlationID != ""
}

// CorrelationIDFromContext returns the request ID, generating a fallback when
// called outside normal HTTP middleware.
func CorrelationIDFromContext(ctx context.Context) string {
	if correlationID, ok := CorrelationID(ctx); ok {
		return correlationID
	}
	FromContext(ctx).Warn("correlation ID not found in context")
	return "gen_" + shortuuid.New()
}
