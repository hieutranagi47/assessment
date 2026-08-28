package http

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestOptionalNullableStringDistinguishesOmittedAndNull(t *testing.T) {
	var omitted UpdateCustomerRequest
	require.NoError(t, json.Unmarshal([]byte(`{}`), &omitted))
	require.Nil(t, omitted.Email)

	var cleared UpdateCustomerRequest
	require.NoError(t, json.Unmarshal([]byte(`{"email":null}`), &cleared))
	require.True(t, cleared.Email.Present)
	require.Nil(t, cleared.Email.Value)

	var supplied UpdateCustomerRequest
	require.NoError(t, json.Unmarshal([]byte(`{"email":"jane@example.com"}`), &supplied))
	require.True(t, supplied.Email.Present)
	require.Equal(t, "jane@example.com", *supplied.Email.Value)
}
