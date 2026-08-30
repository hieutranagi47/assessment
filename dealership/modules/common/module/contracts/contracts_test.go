package contracts

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestContractsVerifyAcceptsEmptyPublishedContracts(t *testing.T) {
	require.NoError(t, (&Contracts{}).Verify())
}
