package app

import (
	"context"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/auth/api/module/client"
	"assessment/modules/common"

	"github.com/google/uuid"
)

// DealershipListRepository is the read port for dealership directory access.
type DealershipListRepository interface {
	CanListDealerships(context.Context, uuid.UUID) (bool, error)
	ListDealerships(context.Context) ([]domain.Dealership, error)
}

// AuthUserInfoLookup is the auth capability required to determine global
// dealership-directory access.
type AuthUserInfoLookup interface {
	GetUserInfo(context.Context, uuid.UUID) (client.UserInfo, error)
}

// ListDealershipsQuery returns every non-deleted dealership to an authorized
// auth administrator or active scheduler admin, staff, or dealer.
type ListDealershipsQuery struct {
	repository DealershipListRepository
	users      AuthUserInfoLookup
}

func NewListDealershipsQuery(repository DealershipListRepository, users AuthUserInfoLookup) *ListDealershipsQuery {
	if repository == nil || users == nil {
		panic("list dealerships query dependencies are required")
	}
	return &ListDealershipsQuery{repository: repository, users: users}
}

func (q *ListDealershipsQuery) List(ctx context.Context, actorUserID uuid.UUID) ([]domain.Dealership, error) {
	if actorUserID == uuid.Nil {
		return nil, common.NewUnauthorizedError("authentication_required", "authentication is required")
	}

	user, err := q.users.GetUserInfo(ctx, actorUserID)
	if err != nil || user.UserID != actorUserID.String() || user.Status != "active" {
		return nil, common.NewForbiddenError("dealership_list_forbidden", "you are not allowed to list dealerships")
	}
	if user.Role == "superadmin" || user.Role == "admin" {
		return q.repository.ListDealerships(ctx)
	}

	allowed, err := q.repository.CanListDealerships(ctx, actorUserID)
	if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, common.NewForbiddenError("dealership_list_forbidden", "you are not allowed to list dealerships")
	}
	return q.repository.ListDealerships(ctx)
}
