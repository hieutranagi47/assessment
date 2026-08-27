// Package client defines the small in-process contract exported by auth.
package client

import (
	"context"

	"github.com/google/uuid"
)

type Identity struct{ UserID uuid.UUID }

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
