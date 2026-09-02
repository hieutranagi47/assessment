package db

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestEmailLookupIsDeterministicAndKeyed(t *testing.T) {
	t.Parallel()

	lookup, err := newEmailLookup("lookup secret")
	require.NoError(t, err)

	require.True(t, bytes.Equal(lookup.lookup("person@example.com"), lookup.lookup("person@example.com")))
	require.False(t, bytes.Equal(lookup.lookup("person@example.com"), lookup.lookup("other@example.com")))

	otherLookup, err := newEmailLookup("other lookup secret")
	require.NoError(t, err)
	require.False(t, bytes.Equal(lookup.lookup("person@example.com"), otherLookup.lookup("person@example.com")))
}

func TestEmailLookupRequiresAKey(t *testing.T) {
	t.Parallel()

	_, err := newEmailLookup("")
	require.Error(t, err)
}
