// Package client defines the small in-process contract exported by auth.
package client

import (
	"context"

	"github.com/google/uuid"
)

// Identity contains access-token claims that have been verified by auth.
// Role is intentionally token-scoped so consuming modules can authorize a
// request without calling back into auth for the same claim.
type Identity struct {
	UserID uuid.UUID
	Role   string
}

// UserInfo is the authorization-relevant user data that auth shares with
// other modules. It intentionally excludes credentials and token material.
type UserInfo struct {
	UserID, Email, FullName, Status, Role string
}
type Authenticator interface {
	AuthenticateAccessToken(string) (Identity, error)
	GetUserInfo(context.Context, uuid.UUID) (UserInfo, error)
	GetUserInfoByEmail(context.Context, string) (UserInfo, error)
}
