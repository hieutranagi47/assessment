package module

import (
	"context"

	"assessment/modules/auth/api/module/client"
	"assessment/modules/auth/app"

	"github.com/google/uuid"
)

type Auth struct{ service *app.Service }

func New(service *app.Service) *Auth {
	return &Auth{
		service,
	}
}

func (a *Auth) AuthenticateAccessToken(raw string) (client.Identity, error) {
	i, e := a.service.Authenticate(raw)
	return client.Identity{UserID: i.UserID}, e
}

// GetUserInfo provides other modules with the current authorization-relevant
// user information without exposing auth's application or persistence layers.
func (a *Auth) GetUserInfo(ctx context.Context, userID uuid.UUID) (client.UserInfo, error) {
	info, err := a.service.UserInfo(ctx, userID)
	return client.UserInfo{UserID: info.UserID, Email: info.Email, FullName: info.FullName, Status: info.Status, Role: info.Role}, err
}

// GetUserInfoByEmail provides other modules with the current
// authorization-relevant user information for an email address.
func (a *Auth) GetUserInfoByEmail(ctx context.Context, email string) (client.UserInfo, error) {
	info, err := a.service.UserInfoByEmail(ctx, email)
	return client.UserInfo{UserID: info.UserID, Email: info.Email, FullName: info.FullName, Status: info.Status, Role: info.Role}, err
}
