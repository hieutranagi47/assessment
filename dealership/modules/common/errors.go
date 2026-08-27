package common

import (
	"fmt"
	"net/http"
)

// Error carries a client-safe error response alongside the internal cause.
type Error struct {
	HttpErrorCode int
	PublicError   string
	ErrorSlug     string
	InternalError error
	Details       []ErrorDetails
}

type ErrorDetails struct {
	EntityType string
	EntityID   string
	ErrorSlug  string
	Message    string
}

// Error implements error while retaining a client-safe message and internal cause.
func (e Error) Error() string {
	s := fmt.Sprintf("%s, Slug: %s", e.PublicError, e.ErrorSlug)
	if e.InternalError != nil {
		s = fmt.Sprintf("%s, InternalError: %s", s, e.InternalError)
	}
	if len(e.Details) > 0 {
		s = fmt.Sprintf("%s, DocumentData: %v", s, e.Details)
	}
	return s
}

// WithDetails appends structured, client-safe detail records.
func (e Error) WithDetails(details []ErrorDetails) Error {
	e.Details = append(e.Details, details...)
	return e
}

// WithInternalError attaches a diagnostic cause that is not exposed by the HTTP mapper.
func (e Error) WithInternalError(err error) Error {
	e.InternalError = err
	return e
}

func NewNotFoundError(slug, format string, args ...any) Error {
	return newError(http.StatusNotFound, slug, format, args...)
}

func NewInvalidInputError(slug, format string, args ...any) Error {
	return newError(http.StatusBadRequest, slug, format, args...)
}

func NewConflictError(slug, format string, args ...any) Error {
	return newError(http.StatusConflict, slug, format, args...)
}

func NewUnauthorizedError(slug, format string, args ...any) Error {
	return newError(http.StatusUnauthorized, slug, format, args...)
}

func NewForbiddenError(slug, format string, args ...any) Error {
	return newError(http.StatusForbidden, slug, format, args...)
}

func NewExpiredError(slug, format string, args ...any) Error {
	return newError(http.StatusGone, slug, format, args...)
}

func newError(code int, slug, format string, args ...any) Error {
	return Error{HttpErrorCode: code, PublicError: fmt.Sprintf(format, args...), ErrorSlug: slug}
}
