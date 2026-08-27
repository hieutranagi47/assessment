package common

// Must returns val or panics when err is non-nil, for use while constructing
// static configuration and test fixtures.
func Must[T any](val T, err any, messageArgs ...any) T {
	if err != nil {
		panic(err)
	}
	return val
}

// ToPtr returns a pointer to val, useful when building optional API fields.
func ToPtr[T any](val T) *T { return &val }
