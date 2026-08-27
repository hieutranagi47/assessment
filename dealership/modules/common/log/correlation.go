package log

import (
	"context"

	"github.com/lithammer/shortuuid/v3"
)

// ContextWithCorrelationID stores a request correlation ID in context.
func ContextWithCorrelationID(ctx context.Context, correlationID string) context.Context {
	return context.WithValue(ctx, correlationIDKey, correlationID)
}

// CorrelationIDFromContext returns the request ID, generating a fallback when
// called outside normal HTTP middleware.
func CorrelationIDFromContext(ctx context.Context) string {
	if correlationID, ok := ctx.Value(correlationIDKey).(string); ok {
		return correlationID
	}
	FromContext(ctx).Warn("correlation ID not found in context")
	return "gen_" + shortuuid.New()
}
