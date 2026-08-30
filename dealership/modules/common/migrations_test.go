package common

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestMigrationFileVersion(t *testing.T) {
	version, err := migrationFileVersion("000123_add_users.up.sql")
	require.NoError(t, err)
	require.EqualValues(t, 123, version)

	for _, name := range []string{"missing.sql", "abc_name.up.sql", "_name.up.sql"} {
		_, err := migrationFileVersion(name)
		require.Error(t, err, name)
	}
}
