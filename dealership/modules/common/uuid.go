package common

import (
	"database/sql/driver"

	"github.com/google/uuid"
)

// UUID is a database- and JSON-compatible domain UUID value.
type UUID [16]byte

// NewUUIDv7 returns a time-ordered UUID suitable for new records.
func NewUUIDv7() UUID {
	u, err := uuid.NewV7()
	if err != nil {
		panic(err)
	}
	return UUID(u)
}

// MustUUIDFromString parses a UUID string and panics when it is invalid.
func MustUUIDFromString(s string) UUID {
	var u UUID
	if err := u.UnmarshalText([]byte(s)); err != nil {
		panic(err)
	}
	return u
}

// String returns the canonical textual UUID representation.
func (u UUID) String() string { return uuid.UUID(u).String() }

// MarshalText implements encoding.TextMarshaler.
func (u UUID) MarshalText() ([]byte, error) { return uuid.UUID(u).MarshalText() }

// Value implements database/sql/driver.Valuer.
func (u UUID) Value() (driver.Value, error) { return uuid.UUID(u).Value() }

// IsZero reports whether the UUID is nil.
func (u UUID) IsZero() bool { return uuid.UUID(u) == uuid.Nil }

// Equals compares two UUID values.
func (u UUID) Equals(other UUID) bool { return u == other }

// UnmarshalText implements encoding.TextUnmarshaler.
func (u *UUID) UnmarshalText(data []byte) error {
	var parsed uuid.UUID
	if err := parsed.UnmarshalText(data); err != nil {
		return err
	}
	*u = UUID(parsed)
	return nil
}

// Scan implements database/sql.Scanner.
func (u *UUID) Scan(src any) error {
	var parsed uuid.UUID
	if err := parsed.Scan(src); err != nil {
		return err
	}
	*u = UUID(parsed)
	return nil
}
