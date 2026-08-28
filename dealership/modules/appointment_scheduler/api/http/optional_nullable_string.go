package http

import "encoding/json"

// OptionalNullableString preserves the difference between an omitted JSON
// field and an explicit null in PATCH requests.
type OptionalNullableString struct {
	Present bool
	Value   *string
}

func (value *OptionalNullableString) UnmarshalJSON(data []byte) error {
	value.Present = true
	if string(data) == "null" {
		value.Value = nil
		return nil
	}
	var decoded string
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	value.Value = &decoded
	return nil
}

// UnmarshalJSON makes explicit null observable even though oapi-codegen uses
// a pointer for optional properties.
func (request *UpdateCustomerRequest) UnmarshalJSON(data []byte) error {
	var decoded struct {
		Name  *string         `json:"name"`
		Phone *string         `json:"phone"`
		Email json.RawMessage `json:"email"`
	}
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	request.Name = decoded.Name
	request.Phone = decoded.Phone
	request.Email = nil
	if decoded.Email != nil {
		value := OptionalNullableString{}
		if err := value.UnmarshalJSON(decoded.Email); err != nil {
			return err
		}
		request.Email = &value
	}
	return nil
}

func (request *UpdateTechnicianRequest) UnmarshalJSON(data []byte) error {
	var decoded struct {
		Name     *string         `json:"name"`
		Phone    *string         `json:"phone"`
		Email    json.RawMessage `json:"email"`
		IsActive *bool           `json:"isActive"`
	}
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	request.Name, request.Phone, request.IsActive, request.Email = decoded.Name, decoded.Phone, decoded.IsActive, nil
	if decoded.Email != nil {
		value := OptionalNullableString{}
		if err := value.UnmarshalJSON(decoded.Email); err != nil {
			return err
		}
		request.Email = &value
	}
	return nil
}
