package domain

import (
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

func TestDealershipAdminNormalizesProfileAndExposesRole(t *testing.T) {
	now := time.Date(2026, 1, 2, 3, 4, 5, 0, time.FixedZone("ICT", 7*60*60))
	phone := " +84900000000 "
	email := " ADMIN@example.com "
	admin, err := NewDealershipAdmin(uuid.New(), uuid.New(), uuid.New(), " Ada ", &phone, &email, now)
	require.NoError(t, err)
	require.Equal(t, "Ada", admin.Name())
	require.Equal(t, "+84900000000", *admin.Phone())
	require.Equal(t, "admin@example.com", *admin.Email())
	require.True(t, admin.IsActive())
	require.Equal(t, "admin", admin.Role())
	require.Equal(t, now.UTC(), admin.CreatedAt())
}

func TestDealershipAdminValidatesReferencesAndContactDetails(t *testing.T) {
	validID := uuid.New()
	_, err := NewDealershipAdmin(uuid.Nil, validID, validID, "Ada", nil, nil, time.Now())
	require.Error(t, err)
	_, err = NewDealershipAdmin(validID, uuid.Nil, validID, "Ada", nil, nil, time.Now())
	require.ErrorIs(t, err, ErrAuthUserIDRequired)
	_, err = NewDealershipAdmin(validID, validID, uuid.Nil, "Ada", nil, nil, time.Now())
	require.ErrorIs(t, err, ErrDealershipIDRequired)
	invalidPhone := "0900000000"
	_, err = NewDealershipAdmin(validID, validID, validID, "Ada", &invalidPhone, nil, time.Now())
	require.ErrorIs(t, err, ErrInvalidAdminPhone)
	invalidEmail := "invalid"
	_, err = NewDealershipAdmin(validID, validID, validID, "Ada", nil, &invalidEmail, time.Now())
	require.ErrorIs(t, err, ErrInvalidAdminEmail)
}
