package http

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"assessment/modules/auth/app"
	"assessment/modules/auth/domain"
	"assessment/modules/common"
	commonlog "assessment/modules/common/log"

	"github.com/google/uuid"
	echo "github.com/labstack/echo/v5"
)

const refreshCookie = "refresh_token"

type (
	identityKey    struct{}
	echoContextKey struct{}
	Handler        struct {
		service *app.Service
	}
)

func NewHandler(service *app.Service) *Handler {
	if service == nil {
		panic("auth service is required")
	}
	return &Handler{service: service}
}

// Register installs generated OpenAPI routes and applies authentication
// middleware only to operations that require an established identity.
func Register(_ context.Context, router common.EchoRouter, h *Handler) error {
	RegisterHandlersWithOptions(router, NewStrictHandler(h, nil), RegisterHandlersOptions{
		BaseURL: "/auth/v1",
		OperationMiddlewares: map[string][]echo.MiddlewareFunc{
			"signIn":            {h.withEchoContext},
			"refreshToken":      {h.withEchoContext},
			"signOutAllDevices": {h.withEchoContext, h.requireIdentity},
			"changePassword":    {h.requireIdentity},
			"updateFullName":    {h.requireIdentity},
			"updateUserStatus":  {h.requireIdentity},
			"updateUserRole":    {h.requireIdentity},
		},
	})
	RegisterDocs(router)
	return nil
}

// CreateSuperadmin creates the first account as the system superadmin.
func (h *Handler) CreateSuperadmin(ctx context.Context, request CreateSuperadminRequestObject) (CreateSuperadminResponseObject, error) {
	if request.Body == nil {
		return CreateSuperadmin400JSONResponse{BadRequestJSONResponse: badRequest("request_body_required", "request body is required")}, nil
	}
	fullName := ""
	if request.Body.FullName != nil {
		fullName = *request.Body.FullName
	}
	id, err := h.service.CreateSuperadmin(ctx, app.SignUpInput{Email: string(request.Body.Email), Password: request.Body.Password, FullName: fullName})
	if err != nil {
		var structured common.Error
		if errors.As(err, &structured) {
			switch structured.HttpErrorCode {
			case http.StatusConflict:
				return CreateSuperadmin409JSONResponse{ConflictJSONResponse: ConflictJSONResponse(errorResponse(err, common.NewConflictError("account_exists", "an account already exists")))}, nil
			case http.StatusBadRequest:
				return CreateSuperadmin400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(err, common.NewInvalidInputError("invalid_request", "invalid request")))}, nil
			}
		}
		if errors.Is(err, app.ErrEmailTaken) {
			return CreateSuperadmin409JSONResponse{ConflictJSONResponse: conflict("email_taken", "email already exists")}, nil
		}
		return nil, err
	}
	return CreateSuperadmin201JSONResponse{UserCreatedJSONResponse: UserCreatedJSONResponse{Id: id}}, nil
}

// SignUp handles user creation and translates application errors to OpenAPI responses.
func (h *Handler) SignUp(ctx context.Context, request SignUpRequestObject) (SignUpResponseObject, error) {
	if request.Body == nil {
		return SignUp400JSONResponse{BadRequestJSONResponse: badRequest("request_body_required", "request body is required")}, nil
	}
	fullName := ""
	if request.Body.FullName != nil {
		fullName = *request.Body.FullName
	}
	id, err := h.service.SignUp(ctx, app.SignUpInput{Email: string(request.Body.Email), Password: request.Body.Password, FullName: fullName})
	if err != nil {
		commonlog.FromContext(ctx).With("error", err).Error("Sign-up failed")
		if errors.Is(err, app.ErrEmailTaken) {
			return SignUp409JSONResponse{ConflictJSONResponse: conflict("email_taken", "email already exists")}, nil
		}
		return SignUp400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(err, common.NewInvalidInputError("invalid_request", "invalid request")))}, nil
	}
	return SignUp201JSONResponse{UserCreatedJSONResponse: UserCreatedJSONResponse{Id: id}}, nil
}

// SignIn authenticates credentials and stores the refresh token in a protected cookie.
func (h *Handler) SignIn(ctx context.Context, request SignInRequestObject) (SignInResponseObject, error) {
	if request.Body == nil {
		return SignIn400JSONResponse{
			BadRequestJSONResponse: badRequest("request_body_required", "request body is required"),
		}, nil
	}
	tokens, err := h.service.SignIn(ctx, string(request.Body.Email), request.Body.Password)
	if err != nil {
		return SignIn401JSONResponse{UnauthorizedJSONResponse: unauthorized("invalid_credentials", "invalid credentials")}, nil
	}
	setRefreshCookieFromContext(ctx, tokens.RefreshToken)
	return SignIn200JSONResponse{TokensJSONResponse: tokensResponse(tokens)}, nil
}

// RefreshToken exchanges the refresh cookie for a new token pair.
func (h *Handler) RefreshToken(ctx context.Context, _ RefreshTokenRequestObject) (RefreshTokenResponseObject, error) {
	cookie, err := echoContextFrom(ctx).Cookie(refreshCookie)
	if err != nil || cookie.Value == "" {
		return RefreshToken401JSONResponse{UnauthorizedJSONResponse: unauthorized("invalid_credentials", "invalid credentials")}, nil
	}
	tokens, err := h.service.Refresh(ctx, cookie.Value)
	if err != nil {
		return RefreshToken401JSONResponse{UnauthorizedJSONResponse: unauthorized("invalid_credentials", "invalid credentials")}, nil
	}
	setRefreshCookieFromContext(ctx, tokens.RefreshToken)
	return RefreshToken200JSONResponse{TokensJSONResponse: tokensResponse(tokens)}, nil
}

// SignOutAllDevices revokes refresh tokens and expires the refresh cookie.
func (h *Handler) SignOutAllDevices(ctx context.Context, _ SignOutAllDevicesRequestObject) (SignOutAllDevicesResponseObject, error) {
	if err := h.service.SignOutAllDevices(ctx, identityFrom(ctx)); err != nil {
		return SignOutAllDevices401JSONResponse{UnauthorizedJSONResponse: unauthorized("authentication_required", "authentication required")}, nil
	}
	expireRefreshCookieFromContext(ctx)
	return SignOutAllDevices204Response{}, nil
}

// ChangePassword changes the authenticated user's password and maps use-case errors.
func (h *Handler) ChangePassword(ctx context.Context, request ChangePasswordRequestObject) (ChangePasswordResponseObject, error) {
	if request.Body == nil {
		return ChangePassword400JSONResponse{BadRequestJSONResponse: badRequest("request_body_required", "request body is required")}, nil
	}
	signOutAll := request.Body.SignOutAll != nil && *request.Body.SignOutAll
	err := h.service.ChangePassword(ctx, identityFrom(ctx), uuid.UUID(request.Id), request.Body.Password, request.Body.NewPassword, signOutAll)
	return changePasswordResponse(err)
}

// UpdateFullName updates the authenticated user's display name.
func (h *Handler) UpdateFullName(ctx context.Context, request UpdateFullNameRequestObject) (UpdateFullNameResponseObject, error) {
	if request.Body == nil {
		return UpdateFullName400JSONResponse{BadRequestJSONResponse: badRequest("request_body_required", "request body is required")}, nil
	}
	err := h.service.UpdateFullName(ctx, identityFrom(ctx), uuid.UUID(request.Id), request.Body.FullName)
	return updateFullNameResponse(err)
}

// UpdateUserStatus updates the authenticated user's lifecycle status.
func (h *Handler) UpdateUserStatus(ctx context.Context, request UpdateUserStatusRequestObject) (UpdateUserStatusResponseObject, error) {
	if request.Body == nil {
		return UpdateUserStatus400JSONResponse{BadRequestJSONResponse: badRequest("request_body_required", "request body is required")}, nil
	}
	err := h.service.UpdateStatus(ctx, identityFrom(ctx), uuid.UUID(request.Id), domain.Status(request.Body.Status))
	return updateStatusResponse(err)
}

// UpdateUserRole assigns a role to another account when the caller is the
// current superadmin.
func (h *Handler) UpdateUserRole(ctx context.Context, request UpdateUserRoleRequestObject) (UpdateUserRoleResponseObject, error) {
	if request.Body == nil {
		return UpdateUserRole400JSONResponse{BadRequestJSONResponse: badRequest("request_body_required", "request body is required")}, nil
	}
	err := h.service.UpdateRole(ctx, identityFrom(ctx), uuid.UUID(request.Id), string(request.Body.Role))
	return updateRoleResponse(err)
}

// requireIdentity verifies the access token and stores only the user ID in request context.
func (h *Handler) requireIdentity(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		identity, err := h.service.Authenticate(bearerToken(c.Request()))
		if err != nil {
			return c.JSON(http.StatusUnauthorized, unauthorized("authentication_required", "authentication required"))
		}
		c.SetRequest(c.Request().WithContext(context.WithValue(c.Request().Context(), identityKey{}, identity.UserID)))
		return next(c)
	}
}

// errorResponse maps a transport-agnostic common.Error into the OpenAPI model.
// The fallback is used for errors that have not yet been given a client-safe
// error shape by the application layer.
func errorResponse(err error, fallback common.Error) ErrorResponse {
	var structured common.Error
	if !errors.As(err, &structured) {
		var structuredPtr *common.Error
		if !errors.As(err, &structuredPtr) || structuredPtr == nil {
			structured = fallback
		} else {
			structured = *structuredPtr
		}
	}

	details := make([]ErrorDetail, 0, len(structured.Details))
	for _, detail := range structured.Details {
		details = append(details, ErrorDetail{
			EntityType: detail.EntityType,
			EntityId:   detail.EntityID,
			ErrorSlug:  detail.ErrorSlug,
			Message:    detail.Message,
		})
	}
	return ErrorResponse{Message: structured.PublicError, Slug: structured.ErrorSlug, Details: details}
}

func badRequest(slug, message string) BadRequestJSONResponse {
	return BadRequestJSONResponse(errorResponse(nil, common.NewInvalidInputError(slug, "%s", message)))
}

func unauthorized(slug, message string) UnauthorizedJSONResponse {
	return UnauthorizedJSONResponse(errorResponse(nil, common.NewUnauthorizedError(slug, "%s", message)))
}

func conflict(slug, message string) ConflictJSONResponse {
	return ConflictJSONResponse(errorResponse(nil, common.NewConflictError(slug, "%s", message)))
}

// withEchoContext makes Echo available to strict handlers that set cookies.
func (h *Handler) withEchoContext(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c *echo.Context) error {
		c.SetRequest(c.Request().WithContext(context.WithValue(c.Request().Context(), echoContextKey{}, c)))
		return next(c)
	}
}

// identityFrom retrieves the authenticated user ID, or uuid.Nil when absent.
func identityFrom(ctx context.Context) uuid.UUID {
	value, _ := ctx.Value(identityKey{}).(uuid.UUID)
	return value
}

// echoContextFrom retrieves the Echo context installed by withEchoContext.
func echoContextFrom(ctx context.Context) *echo.Context {
	value, _ := ctx.Value(echoContextKey{}).(*echo.Context)
	return value
}

// bearerToken extracts a Bearer header, then falls back to the access cookie.
func bearerToken(request *http.Request) string {
	fields := strings.Fields(request.Header.Get("Authorization"))
	if len(fields) == 2 && strings.EqualFold(fields[0], "bearer") {
		return fields[1]
	}
	cookie, err := request.Cookie("access_token")
	if err == nil {
		return cookie.Value
	}
	return ""
}

// tokensResponse omits the refresh token from the JSON response body.
func tokensResponse(tokens app.Tokens) TokensJSONResponse {
	return TokensJSONResponse{AccessToken: tokens.AccessToken, ExpiresIn: tokens.ExpiresIn, TokenType: tokens.TokenType}
}

// setRefreshCookieFromContext writes a protected refresh-token cookie.
func setRefreshCookieFromContext(ctx context.Context, value string) {
	echoContextFrom(ctx).SetCookie(&http.Cookie{Name: refreshCookie, Value: value, Path: "/auth", MaxAge: int((7 * 24 * time.Hour).Seconds()), HttpOnly: true, Secure: true, SameSite: http.SameSiteStrictMode})
}

func expireRefreshCookieFromContext(ctx context.Context) {
	echoContextFrom(ctx).SetCookie(&http.Cookie{Name: refreshCookie, Value: "", Path: "/auth", MaxAge: -1, HttpOnly: true, Secure: true, SameSite: http.SameSiteStrictMode})
}

// changePasswordResponse maps password use-case errors to API responses.
func changePasswordResponse(err error) (ChangePasswordResponseObject, error) {
	if err == nil {
		return ChangePassword204Response{}, nil
	}
	if errors.Is(err, app.ErrForbidden) {
		return ChangePassword403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(errorResponse(err, common.NewForbiddenError("forbidden", "action is not permitted")))}, nil
	}
	if errors.Is(err, app.ErrNotFound) {
		return ChangePassword404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(errorResponse(err, common.NewNotFoundError("user_not_found", "user not found")))}, nil
	}
	if errors.Is(err, app.ErrInvalidCredentials) {
		return ChangePassword401JSONResponse{UnauthorizedJSONResponse: unauthorized("invalid_credentials", "invalid credentials")}, nil
	}
	return ChangePassword400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(err, common.NewInvalidInputError("invalid_request", "invalid request")))}, nil
}

// updateFullNameResponse maps name-update errors to API responses.
func updateFullNameResponse(err error) (UpdateFullNameResponseObject, error) {
	if err == nil {
		return UpdateFullName204Response{}, nil
	}
	if errors.Is(err, app.ErrForbidden) {
		return UpdateFullName403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(errorResponse(err, common.NewForbiddenError("forbidden", "action is not permitted")))}, nil
	}
	if errors.Is(err, app.ErrNotFound) {
		return UpdateFullName404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(errorResponse(err, common.NewNotFoundError("user_not_found", "user not found")))}, nil
	}
	return UpdateFullName400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(err, common.NewInvalidInputError("invalid_request", "invalid request")))}, nil
}

// updateStatusResponse maps status-update errors to API responses.
func updateStatusResponse(err error) (UpdateUserStatusResponseObject, error) {
	if err == nil {
		return UpdateUserStatus204Response{}, nil
	}
	if errors.Is(err, app.ErrForbidden) {
		return UpdateUserStatus403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(errorResponse(err, common.NewForbiddenError("forbidden", "action is not permitted")))}, nil
	}
	if errors.Is(err, app.ErrNotFound) {
		return UpdateUserStatus404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(errorResponse(err, common.NewNotFoundError("user_not_found", "user not found")))}, nil
	}
	return UpdateUserStatus400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(err, common.NewInvalidInputError("invalid_request", "invalid request")))}, nil
}

// updateRoleResponse maps account-administration errors to API responses.
func updateRoleResponse(err error) (UpdateUserRoleResponseObject, error) {
	if err == nil {
		return UpdateUserRole204Response{}, nil
	}
	if errors.Is(err, app.ErrForbidden) {
		return UpdateUserRole403JSONResponse{ForbiddenJSONResponse: ForbiddenJSONResponse(errorResponse(err, common.NewForbiddenError("forbidden", "action is not permitted")))}, nil
	}
	if errors.Is(err, app.ErrNotFound) {
		return UpdateUserRole404JSONResponse{NotFoundJSONResponse: NotFoundJSONResponse(errorResponse(err, common.NewNotFoundError("user_not_found", "user not found")))}, nil
	}
	return UpdateUserRole400JSONResponse{BadRequestJSONResponse: BadRequestJSONResponse(errorResponse(err, common.NewInvalidInputError("invalid_role", "invalid role")))}, nil
}

var _ StrictServerInterface = (*Handler)(nil)
