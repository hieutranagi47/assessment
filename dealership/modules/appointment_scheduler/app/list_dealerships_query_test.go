package app

import (
	"context"
	"errors"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/auth/api/module/client"
	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type dealershipListRepositoryStub struct {
	allowed       bool
	items         []domain.Dealership
	listWasCalled bool
}

func (s *dealershipListRepositoryStub) CanListDealerships(context.Context, uuid.UUID) (bool, error) {
	return s.allowed, nil
}

func (s *dealershipListRepositoryStub) ListDealerships(context.Context) ([]domain.Dealership, error) {
	s.listWasCalled = true
	return s.items, nil
}

func TestListDealershipsQueryAuthorizesAuthAndSchedulerRoles(t *testing.T) {
	actorID := uuid.New()
	dealership, err := domain.NewDealership(uuid.New(), "Downtown Motors", "DTM", "1 Main Street", "Asia/Ho_Chi_Minh", time.Now())
	require.NoError(t, err)

	tests := []struct {
		name    string
		user    client.UserInfo
		allowed bool
		wantErr string
	}{
		{name: "superadmin", user: client.UserInfo{UserID: actorID.String(), Status: "active", Role: "superadmin"}},
		{name: "auth admin", user: client.UserInfo{UserID: actorID.String(), Status: "active", Role: "admin"}},
		{name: "scheduler staff", user: client.UserInfo{UserID: actorID.String(), Status: "active", Role: "user"}, allowed: true},
		{name: "scheduler dealer", user: client.UserInfo{UserID: actorID.String(), Status: "active", Role: "user"}, allowed: true},
		{name: "ordinary user", user: client.UserInfo{UserID: actorID.String(), Status: "active", Role: "user"}, wantErr: "dealership_list_forbidden"},
		{name: "disabled auth admin", user: client.UserInfo{UserID: actorID.String(), Status: "disabled", Role: "admin"}, wantErr: "dealership_list_forbidden"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			repository := &dealershipListRepositoryStub{allowed: test.allowed, items: []domain.Dealership{dealership}}
			query := NewListDealershipsQuery(repository, userInfoStub{info: test.user})
			items, err := query.List(context.Background(), actorID)
			if test.wantErr != "" {
				var structured common.Error
				require.Error(t, err)
				require.ErrorAs(t, err, &structured)
				require.Equal(t, test.wantErr, structured.ErrorSlug)
				require.False(t, repository.listWasCalled)
				return
			}
			require.NoError(t, err)
			require.Equal(t, []domain.Dealership{dealership}, items)
			require.True(t, repository.listWasCalled)
		})
	}
}

func TestListDealershipsQueryRequiresAuthentication(t *testing.T) {
	repository := &dealershipListRepositoryStub{}
	query := NewListDealershipsQuery(repository, userInfoStub{err: errors.New("not called")})

	_, err := query.List(context.Background(), uuid.Nil)
	var structured common.Error
	require.ErrorAs(t, err, &structured)
	require.Equal(t, "authentication_required", structured.ErrorSlug)
	require.False(t, repository.listWasCalled)
}
