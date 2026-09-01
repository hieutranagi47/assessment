package db

import (
	"context"
	"errors"
	"time"

	"assessment/modules/auth/adapters/db/dbmodels"
	"assessment/modules/auth/app"
	"assessment/modules/auth/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	database *pgxpool.Pool
	queries  *dbmodels.Queries
	emails   emailCrypto
}

// NewRepository creates the PostgreSQL adapter. Email encryption and lookup
// tokens are computed in this adapter, so database queries never receive keys.
func NewRepository(database *pgxpool.Pool, emailEncryptionKey, emailLookupKey string) *Repository {
	if database == nil {
		panic("auth database pool is required")
	}
	emails, err := newEmailCrypto(emailEncryptionKey, emailLookupKey)
	if err != nil {
		panic(err)
	}
	return &Repository{database: database, queries: dbmodels.New(database), emails: emails}
}

// Create persists the domain user and maps PostgreSQL's duplicate-key error to the
// application-level email conflict.
func (r *Repository) Create(ctx context.Context, user domain.User) error {
	return r.createWithRole(ctx, user, "user", false)
}

// CreateSuperadmin creates a user and its superadmin role only when no auth
// account exists. All account creation transactions share an advisory lock,
// making the empty-table check safe against both setup and normal sign-up races.
func (r *Repository) CreateSuperadmin(ctx context.Context, user domain.User) error {
	return r.createWithRole(ctx, user, "superadmin", true)
}

func (r *Repository) createWithRole(ctx context.Context, user domain.User, role string, onlyOne bool) error {
	encryptedEmail, err := r.emails.encrypt(user.Email())
	if err != nil {
		return err
	}
	previous := user.PreviousPasswordHashes()
	err = common.UpdateInTx(ctx, r.database, func(ctx context.Context, tx pgx.Tx) error {
		queries := r.queries.WithTx(tx)
		if err := queries.LockInitialAccountCreation(ctx); err != nil {
			return err
		}
		if onlyOne {
			exists, err := queries.HasAnyUser(ctx)
			if err != nil {
				return err
			}
			if exists {
				return app.ErrAccountExists
			}
		}
		if err := queries.CreateUser(ctx, dbmodels.CreateUserParams{UserID: user.ID().String(), Email: encryptedEmail, EmailLookup: r.emails.lookup(user.Email()), FullName: user.FullName(), HashedPassword: user.PasswordHash(), HashedPassword1: previous[0], HashedPassword2: previous[1], TokenVer: int32(user.TokenVersion()), Status: string(user.Status()), CreatedAt: user.CreatedAt(), UpdatedAt: user.UpdatedAt()}); err != nil {
			return err
		}
		return queries.CreateUserRole(ctx, dbmodels.CreateUserRoleParams{UserID: user.ID().String(), RoleName: role, CreatedAt: user.CreatedAt(), UpdatedAt: user.UpdatedAt()})
	})
	if isDuplicateEmail(err) {
		return app.ErrEmailTaken
	}
	return err
}

// FindByEmail loads and decrypts the email before restoring the domain user.
func (r *Repository) FindByEmail(ctx context.Context, email string) (domain.User, error) {
	value, err := r.queries.GetUserByEmail(ctx, r.emails.lookup(email))
	decryptedEmail, decryptErr := r.emails.decrypt(value.Email)
	if err == nil && decryptErr != nil {
		err = decryptErr
	}
	return toDomain(value.UserID, decryptedEmail, value.FullName, value.HashedPassword, value.HashedPassword1, value.HashedPassword2, value.TokenVer, value.Status, value.CreatedAt, value.UpdatedAt, err)
}

// FindSignInUserByEmail loads a user and its role in one query so the access
// token is issued from one consistent authentication read.
func (r *Repository) FindSignInUserByEmail(ctx context.Context, email string) (app.AuthenticatedUser, error) {
	value, err := r.queries.GetSignInUserByEmail(ctx, r.emails.lookup(email))
	decryptedEmail, decryptErr := r.emails.decrypt(value.Email)
	if err == nil && decryptErr != nil {
		err = decryptErr
	}
	user, err := toDomain(
		value.UserID,
		decryptedEmail,
		value.FullName,
		value.HashedPassword,
		value.HashedPassword1,
		value.HashedPassword2,
		value.TokenVer,
		value.Status,
		value.CreatedAt,
		value.UpdatedAt,
		err,
	)
	if err != nil {
		return app.AuthenticatedUser{}, err
	}
	return app.AuthenticatedUser{User: user, Role: value.Role}, nil
}

// FindRefreshUserByID loads a user and its current role in one query before
// a refresh token is exchanged for a new access token.
func (r *Repository) FindRefreshUserByID(ctx context.Context, id uuid.UUID) (app.AuthenticatedUser, error) {
	value, err := r.queries.GetRefreshUserByID(ctx, id.String())
	decryptedEmail, decryptErr := r.emails.decrypt(value.Email)
	if err == nil && decryptErr != nil {
		err = decryptErr
	}
	user, err := toDomain(
		value.UserID,
		decryptedEmail,
		value.FullName,
		value.HashedPassword,
		value.HashedPassword1,
		value.HashedPassword2,
		value.TokenVer,
		value.Status,
		value.CreatedAt,
		value.UpdatedAt,
		err,
	)
	if err != nil {
		return app.AuthenticatedUser{}, err
	}
	return app.AuthenticatedUser{User: user, Role: value.Role}, nil
}

// FindByID loads a user by UUID and restores it through domain validation.
func (r *Repository) FindByID(ctx context.Context, id uuid.UUID) (domain.User, error) {
	value, err := r.queries.GetUserByID(ctx, id.String())
	decryptedEmail, decryptErr := r.emails.decrypt(value.Email)
	if err == nil && decryptErr != nil {
		err = decryptErr
	}
	return toDomain(value.UserID, decryptedEmail, value.FullName, value.HashedPassword, value.HashedPassword1, value.HashedPassword2, value.TokenVer, value.Status, value.CreatedAt, value.UpdatedAt, err)
}

// FindRole returns the role currently assigned to a user.
func (r *Repository) FindRole(ctx context.Context, id uuid.UUID) (string, error) {
	role, err := r.queries.GetUserRole(ctx, id.String())
	if errors.Is(err, pgx.ErrNoRows) {
		return "", app.ErrNotFound
	}
	return role, err
}

// UpdateRole assigns a known role to an existing account. The application
// service validates both before calling this adapter; CreateUserRole performs
// an atomic insert-or-update for the assignment.
func (r *Repository) UpdateRole(ctx context.Context, id uuid.UUID, role string, updatedAt time.Time) error {
	return r.queries.CreateUserRole(ctx, dbmodels.CreateUserRoleParams{
		UserID:    id.String(),
		RoleName:  role,
		CreatedAt: updatedAt.UTC(),
		UpdatedAt: updatedAt.UTC(),
	})
}

// Update writes the complete mutable user state and reports a missing row as
// the application not-found error.
func (r *Repository) Update(ctx context.Context, user domain.User) error {
	previous := user.PreviousPasswordHashes()
	rows, err := r.queries.UpdateUser(ctx, dbmodels.UpdateUserParams{UserID: user.ID().String(), FullName: user.FullName(), HashedPassword: user.PasswordHash(), HashedPassword1: previous[0], HashedPassword2: previous[1], TokenVer: int32(user.TokenVersion()), Status: string(user.Status()), UpdatedAt: user.UpdatedAt()})
	if err != nil {
		return err
	}
	if rows == 0 {
		return app.ErrNotFound
	}
	return nil
}

// toDomain converts generated SQL models into the domain model while mapping
// pgx.ErrNoRows to the application port's stable not-found error.
func toDomain(idValue, email, fullName, passwordHash, passwordHash1, passwordHash2 string, tokenVer int32, status string, createdAt, updatedAt time.Time, err error) (domain.User, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, app.ErrNotFound
	}
	if err != nil {
		return domain.User{}, err
	}
	id, parseErr := uuid.Parse(idValue)
	if parseErr != nil {
		return domain.User{}, parseErr
	}
	return domain.RestoreUser(id, email, fullName, passwordHash, [2]string{passwordHash1, passwordHash2}, int(tokenVer), domain.Status(status), createdAt, updatedAt)
}

// isDuplicateEmail recognizes PostgreSQL's duplicate-key code without coupling
// application services to driver-specific errors.
func isDuplicateEmail(err error) bool {
	if err == nil {
		return false
	}
	var postgresErr *pgconn.PgError
	return errors.As(err, &postgresErr) && postgresErr.Code == "23505"
}
