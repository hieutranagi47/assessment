package common

import (
	"database/sql/driver"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestUUIDTextRoundTrip(t *testing.T) {
	original := NewUUIDv7()
	var decoded UUID
	text, err := original.MarshalText()
	if err != nil {
		t.Fatal(err)
	}
	if err := decoded.UnmarshalText(text); err != nil {
		t.Fatal(err)
	}
	if !original.Equals(decoded) || decoded.IsZero() {
		t.Fatalf("UUID round trip failed: %s != %s", original, decoded)
	}
}

func TestUUIDDatabaseAndPanicHelpers(t *testing.T) {
	uuid := MustUUIDFromString("018f1b72-9b6a-7a32-b591-7782ad7b5ebd")
	require.Equal(t, "018f1b72-9b6a-7a32-b591-7782ad7b5ebd", uuid.String())
	value, err := uuid.Value()
	require.NoError(t, err)
	require.Equal(t, driver.Value("018f1b72-9b6a-7a32-b591-7782ad7b5ebd"), value)

	var scanned UUID
	require.NoError(t, scanned.Scan(value))
	require.True(t, scanned.Equals(uuid))
	require.Panics(t, func() { MustUUIDFromString("invalid") })
}
