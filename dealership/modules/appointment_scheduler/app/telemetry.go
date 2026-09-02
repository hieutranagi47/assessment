package app

import (
	"context"
	"errors"
	"net/http"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
)

// AppointmentTelemetry observes application use cases without making the
// domain model depend on a telemetry SDK.
type AppointmentTelemetry interface {
	StartScheduleAppointment(context.Context, ScheduleAppointmentTraceMetadata) (context.Context, func(ScheduleAppointmentTraceResult, error))
	StartAppointmentTransition(context.Context, AppointmentTransitionTraceMetadata) (context.Context, func(error))
}

type noopAppointmentTelemetry struct{}

// ScheduleAppointmentTraceMetadata contains only identifiers that are safe to
// attach to an application span before the scheduling operation begins.
type ScheduleAppointmentTraceMetadata struct {
	ActorID       uuid.UUID
	CustomerID    uuid.UUID
	VehicleID     uuid.UUID
	ServiceTypeID uuid.UUID
	TechnicianID  uuid.UUID
	ServiceBayID  uuid.UUID
}

// ScheduleAppointmentTraceResult contains successful-operation summary data.
// It deliberately excludes the appointment response payload.
type ScheduleAppointmentTraceResult struct {
	AppointmentID uuid.UUID
	DealershipID  uuid.UUID
}

// AppointmentTransitionTraceMetadata contains only identifiers and lifecycle
// state needed to describe a transition span.
type AppointmentTransitionTraceMetadata struct {
	ActorID       uuid.UUID
	AppointmentID uuid.UUID
	From          domain.AppointmentStatus
	To            domain.AppointmentStatus
}

func (noopAppointmentTelemetry) StartScheduleAppointment(ctx context.Context, _ ScheduleAppointmentTraceMetadata) (context.Context, func(ScheduleAppointmentTraceResult, error)) {
	return ctx, func(ScheduleAppointmentTraceResult, error) {}
}

func (noopAppointmentTelemetry) StartAppointmentTransition(ctx context.Context, _ AppointmentTransitionTraceMetadata) (context.Context, func(error)) {
	return ctx, func(error) {}
}

// AppointmentOutcome classifies a use-case result without exposing its details.
func AppointmentOutcome(err error) string {
	if err == nil {
		return "success"
	}

	if errors.Is(err, ErrAppointmentUnavailable) {
		return "conflict"
	}

	var applicationError common.Error
	if errors.As(err, &applicationError) {
		switch applicationError.HttpErrorCode {
		case 400:
			return "validation_error"
		case 409:
			return "conflict"
		}
	}

	return "error"
}

// AppointmentStatusCode returns the response status associated with a result.
func AppointmentStatusCode(err error, successStatus int) int {
	if err == nil {
		return successStatus
	}

	var applicationError common.Error
	if errors.As(err, &applicationError) && applicationError.HttpErrorCode != 0 {
		return applicationError.HttpErrorCode
	}

	return http.StatusInternalServerError
}
