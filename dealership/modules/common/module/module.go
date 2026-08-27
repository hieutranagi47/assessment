package module

import (
	"context"

	"assessment/modules/common"
	"assessment/modules/common/module/contracts"
)

type Name string

// Module defines the common lifecycle for independently-owned application
// boundaries. Concrete modules only depend inward on common abstractions.
type Module interface {
	Name() Name
	Init(context.Context) error
	RegisterHttp(context.Context, common.EchoRouter) error
	RegisterContracts(context.Context, *contracts.Contracts) error
}
