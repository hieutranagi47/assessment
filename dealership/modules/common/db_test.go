package common

import (
	"errors"
	"testing"

	"github.com/jackc/pgerrcode"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/stretchr/testify/require"
)

func TestIsUniqueViolationErrorMatchesOnlyRequestedConstraint(t *testing.T) {
	unique := &pgconn.PgError{Code: pgerrcode.UniqueViolation, ConstraintName: "users_email_key"}
	require.True(t, IsUniqueViolationError(unique, "users_email_key"))
	require.True(t, IsUniqueViolationError(errors.Join(errors.New("wrapped"), unique), "users_email_key"))
	require.False(t, IsUniqueViolationError(unique, "other_key"))
	require.False(t, IsUniqueViolationError(&pgconn.PgError{Code: pgerrcode.ForeignKeyViolation, ConstraintName: "users_email_key"}, "users_email_key"))
	require.False(t, IsUniqueViolationError(nil, "users_email_key"))
}
