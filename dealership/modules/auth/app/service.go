package app

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode"

	"assessment/modules/auth/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
)

var (
	ErrEmailTaken         = errors.New("email already exists")
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrForbidden          = errors.New("forbidden")
	ErrNotFound           = errors.New("user not found")
	ErrAccountExists      = errors.New("an account already exists")
)

type Repository interface {
	Create(context.Context, domain.User, string) error
	CreateSuperadmin(context.Context, domain.User, string) error
	FindByEmail(context.Context, string) (domain.User, error)
	FindSignInUserByEmail(context.Context, string) (AuthenticatedUser, error)
	FindByID(context.Context, uuid.UUID) (domain.User, error)
	FindRefreshUserByID(context.Context, uuid.UUID) (AuthenticatedUser, error)
	FindRole(context.Context, uuid.UUID) (string, error)
	UpdateRole(context.Context, uuid.UUID, string, time.Time) error
	Update(context.Context, domain.User) error
	UpdatePassword(context.Context, domain.User) error
	StoreDeliveryEmail(context.Context, uuid.UUID, string) error
}

// AuthenticatedUser is the credential and authorization data loaded atomically
// for token issuance. Its role is read from auth.user_roles joined to auth.roles.
type AuthenticatedUser struct {
	User domain.User
	Role string
}
type TokenIssuer interface {
	Issue(domain.User, string) (Tokens, error)
	VerifyAccess(string) (Identity, error)
	VerifyRefresh(string) (Identity, error)
}
type PasswordHasher interface {
	Hash(string) (string, error)
	Matches(string, string) bool
}
type Tokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"-"`
	ExpiresIn    int    `json:"expires_in"`
	TokenType    string `json:"token_type"`
}
type Identity struct {
	UserID       uuid.UUID
	TokenVersion int
	Plan         string
	Role         string
}

// UserInfo is the current authorization-relevant view of a user. It is kept
// separate from Identity because access tokens intentionally contain only
// claims that are safe to validate without a database lookup.
type UserInfo struct {
	UserID, Email, FullName, Status, Role string
}
type Service struct {
	repo      Repository
	tokens    TokenIssuer
	passwords PasswordHasher
	now       func() time.Time
}

// NewService wires the authentication use cases to their ports. Dependencies
// are mandatory because silently accepting a missing security component would
// make the service fail only when a request reaches that code path.
func NewService(repo Repository, tokens TokenIssuer, passwords PasswordHasher) *Service {
	if repo == nil || tokens == nil || passwords == nil {
		panic("auth dependencies are required")
	}
	return &Service{repo: repo, tokens: tokens, passwords: passwords, now: time.Now}
}

type SignUpInput struct{ Email, FullName, Password string }

// SignUp validates and hashes credentials, creates the domain user, and
// persists it. The repository translates a duplicate email into ErrEmailTaken.
func (s *Service) SignUp(ctx context.Context, input SignUpInput) (uuid.UUID, error) {
	return s.createUser(ctx, input, s.repo.Create)
}

// CreateSuperadmin creates the initial privileged account while reusing the
// same validation and credential handling as normal sign-up. The repository
// enforces the first-account-only invariant atomically.
func (s *Service) CreateSuperadmin(ctx context.Context, input SignUpInput) (uuid.UUID, error) {
	return s.createUser(ctx, input, s.repo.CreateSuperadmin)
}

func (s *Service) createUser(ctx context.Context, input SignUpInput, create func(context.Context, domain.User, string) error) (uuid.UUID, error) {
	// BEGIN: Form validation
	errDetails := []common.ErrorDetails{}
	if strings.TrimSpace(input.Password) == "" {
		err := domain.ErrPasswordPattern.Error()
		errDetails = append(errDetails, common.ErrorDetails{
			EntityType: "input-validate",
			EntityID:   "password",
			ErrorSlug:  "signup-password",
			Message:    err,
		})
		return uuid.Nil, common.NewInvalidInputError(
			"signup",
			"auth service : %s",
			"invalid credential",
		).WithDetails(errDetails)
	}
	err := validatePasswordPattern(input.Password)
	if err != nil {
		errDetails = append(errDetails, common.ErrorDetails{
			EntityType: "input-validate",
			EntityID:   "password",
			ErrorSlug:  "signup-password",
			Message:    err.Error(),
		})

		return uuid.Nil, common.NewInvalidInputError(
			"signup",
			"auth service : %s",
			"invalid credential",
		).WithDetails(errDetails)
	}
	// END: Form validation

	hash, err := s.passwords.Hash(input.Password)
	if err != nil {
		return uuid.Nil, err
	}
	user, err := domain.NewUser(uuid.New(), input.Email, input.FullName, hash, s.now())
	if err != nil {
		return uuid.Nil, common.NewInvalidInputError("signup", "invalid credential").WithDetails([]common.ErrorDetails{{
			EntityType: "input-validate",
			EntityID:   "email",
			ErrorSlug:  "signup-email",
			Message:    err.Error(),
		}})
	}
	if err := create(ctx, user, input.Password); err != nil {
		if errors.Is(err, ErrAccountExists) {
			return uuid.Nil, common.NewConflictError("account_exists", "an account already exists")
		}
		return uuid.Nil, err
	}
	return user.ID(), nil
}

// SignIn authenticates an email and password and issues access and refresh
// tokens. All authentication failures intentionally collapse to one error.
func (s *Service) SignIn(ctx context.Context, email, password string, storeDeliveryEmail bool) (Tokens, error) {
	signInUser, err := s.repo.FindSignInUserByEmail(ctx, strings.ToLower(strings.TrimSpace(email)))
	if err != nil || !s.passwords.Matches(signInUser.User.PasswordHash(), password) || signInUser.User.CanSignIn() != nil {
		return Tokens{}, ErrInvalidCredentials
	}
	if storeDeliveryEmail {
		if err := s.repo.StoreDeliveryEmail(ctx, signInUser.User.ID(), signInUser.User.Email()); err != nil {
			return Tokens{}, err
		}
	}
	return s.tokens.Issue(signInUser.User, signInUser.Role)
}

// Refresh verifies a refresh token and compares its embedded token version
// with storage, preventing revoked tokens from being exchanged again.
func (s *Service) Refresh(ctx context.Context, rawToken string) (Tokens, error) {
	identity, err := s.tokens.VerifyRefresh(rawToken)
	if err != nil {
		return Tokens{}, ErrInvalidCredentials
	}
	refreshUser, err := s.repo.FindRefreshUserByID(ctx, identity.UserID)
	if err != nil || refreshUser.User.TokenVersion() != identity.TokenVersion || refreshUser.User.CanSignIn() != nil {
		return Tokens{}, ErrInvalidCredentials
	}
	return s.tokens.Issue(refreshUser.User, refreshUser.Role)
}

// SignOutAllDevices revokes every refresh token issued for the authenticated
// user. Access tokens remain valid until their normal short expiry.
func (s *Service) SignOutAllDevices(ctx context.Context, userID uuid.UUID) error {
	user, err := s.repo.FindByID(ctx, userID)
	if err != nil {
		return ErrInvalidCredentials
	}
	user.RevokeRefreshTokens(s.now())
	if err := s.repo.Update(ctx, user); err != nil {
		return ErrInvalidCredentials
	}
	return nil
}

// Authenticate verifies an access token and returns the caller identity.
func (s *Service) Authenticate(rawToken string) (Identity, error) {
	return s.tokens.VerifyAccess(rawToken)
}

// UserInfo returns the current user data needed by other bounded contexts to
// make authorization decisions. Looking up the role on each privileged action
// ensures role changes take effect without waiting for an access token to
// expire.
func (s *Service) UserInfo(ctx context.Context, id uuid.UUID) (UserInfo, error) {
	user, err := s.repo.FindByID(ctx, id)
	return s.userInfo(ctx, user, err)
}

// UserInfoByEmail returns the current user data needed by other bounded
// contexts to resolve an auth user from its stable email address.
func (s *Service) UserInfoByEmail(ctx context.Context, email string) (UserInfo, error) {
	normalizedEmail := strings.ToLower(strings.TrimSpace(email))
	user, err := s.repo.FindByEmail(ctx, normalizedEmail)
	return s.userInfo(ctx, user, err)
}

func (s *Service) userInfo(ctx context.Context, user domain.User, err error) (UserInfo, error) {
	if err != nil {
		return UserInfo{}, err
	}
	role, err := s.repo.FindRole(ctx, user.ID())
	if err != nil {
		return UserInfo{}, err
	}
	return UserInfo{
		UserID:   user.ID().String(),
		Email:    user.Email(),
		FullName: user.FullName(),
		Status:   string(user.Status()),
		Role:     role,
	}, nil
}

// ChangePassword changes only the authenticated user's password and optionally
// revokes tokens on all devices. Actor/target comparison prevents horizontal
// privilege escalation before any target data is loaded.
func (s *Service) ChangePassword(ctx context.Context, actor, target uuid.UUID, current, next string, signOutAll bool) error {
	if actor != target {
		return ErrForbidden
	}
	err := validatePasswordPattern(next)
	if err != nil {
		return err
	}
	user, err := s.repo.FindByID(ctx, target)
	if err != nil {
		return ErrNotFound
	}
	if !s.passwords.Matches(user.PasswordHash(), current) {
		return ErrInvalidCredentials
	}
	hash, err := s.passwords.Hash(next)
	if err != nil {
		return err
	}
	if err := user.ChangePassword(hash, func(old string) bool { return s.passwords.Matches(old, next) }, signOutAll, s.now()); err != nil {
		return err
	}
	return s.repo.UpdatePassword(ctx, user)
}

// UpdateFullName changes only the authenticated user's full name.
func (s *Service) UpdateFullName(ctx context.Context, actor, target uuid.UUID, name string) error {
	if actor != target {
		return ErrForbidden
	}
	user, err := s.repo.FindByID(ctx, target)
	if err != nil {
		return ErrNotFound
	}
	if err = user.UpdateFullName(name, s.now()); err != nil {
		return err
	}
	return s.repo.Update(ctx, user)
}

// UpdateStatus changes only the authenticated user's account status.
func (s *Service) UpdateStatus(ctx context.Context, actor, target uuid.UUID, status domain.Status) error {
	if actor != target {
		return ErrForbidden
	}
	user, err := s.repo.FindByID(ctx, target)
	if err != nil {
		return ErrNotFound
	}
	if err = user.ChangeStatus(status, s.now()); err != nil {
		return err
	}
	return s.repo.Update(ctx, user)
}

// UpdateRole grants a role to another account. Only the current superadmin
// may do this, and it may never change its own role.
func (s *Service) UpdateRole(ctx context.Context, actor, target uuid.UUID, role string) error {
	if actor == target {
		return ErrForbidden
	}
	actorRole, err := s.repo.FindRole(ctx, actor)
	if err != nil || actorRole != domain.RoleSuperadmin {
		return ErrForbidden
	}
	if !domain.ValidRole(role) {
		return domain.ErrInvalidRole
	}
	if _, err := s.repo.FindByID(ctx, target); err != nil {
		return ErrNotFound
	}
	return s.repo.UpdateRole(ctx, target, role, s.now())
}

// Validate password pattern:
// - atleast one lowercase
// - atleast one uppercase
// - atleast one number
// - atleast one of special characters [@, #, *, -, _]
// Min length 8
// Max length 32

func validatePasswordPattern(pw string) error {
	if len(pw) < 8 || len(pw) > 32 {
		return domain.ErrPasswordPattern
	}
	for _, l := range pw {
		if !unicode.IsNumber(l) && !unicode.IsUpper(l) && !unicode.IsLower(l) && !strings.ContainsRune("@#$*-_", l) {
			return domain.ErrPasswordPattern
		}
	}
	return nil
}
