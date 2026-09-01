package app

import (
	"context"

	"github.com/google/uuid"
)

type authorizationContextKey struct{}

// Authorization is the verified access-token authorization relevant to this
// request. Dealership-specific roles and membership are still checked through
// appointment-scheduler repositories.
type Authorization struct {
	UserID uuid.UUID
	Role   string
}

// WithAuthorization attaches verified token claims at the HTTP boundary.
func WithAuthorization(ctx context.Context, authorization Authorization) context.Context {
	return context.WithValue(ctx, authorizationContextKey{}, authorization)
}

// AuthorizationFrom returns the verified access-token claims on a request.
func AuthorizationFrom(ctx context.Context) (Authorization, bool) {
	authorization, ok := ctx.Value(authorizationContextKey{}).(Authorization)
	if !ok || authorization.UserID == uuid.Nil || authorization.Role == "" {
		return Authorization{}, false
	}
	return authorization, true
}
