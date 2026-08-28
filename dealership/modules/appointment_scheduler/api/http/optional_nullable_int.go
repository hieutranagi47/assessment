package http

import "encoding/json"

// OptionalNullableInt distinguishes omitted, null, and integer PATCH values.
type OptionalNullableInt struct {
	Present bool
	Value   *int
}

func (value *OptionalNullableInt) UnmarshalJSON(data []byte) error {
	value.Present = true
	if string(data) == "null" {
		value.Value = nil
		return nil
	}
	var parsed int
	if err := json.Unmarshal(data, &parsed); err != nil {
		return err
	}
	value.Value = &parsed
	return nil
}
