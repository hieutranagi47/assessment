package common

import "testing"

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
