package common

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestMustReturnsValueOrPanics(t *testing.T) {
	require.Equal(t, 42, Must(42, nil))
	require.PanicsWithError(t, "failed", func() { Must(0, errors.New("failed")) })
}

func TestToPtrReturnsIndependentAddressableValue(t *testing.T) {
	value := ToPtr("original")
	*value = "changed"
	require.Equal(t, "changed", *value)
}
