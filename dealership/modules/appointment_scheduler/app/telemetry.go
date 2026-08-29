package app

import (
	"context"
	"errors"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/common"
)

// AppointmentTelemetry observes application use cases without making the
// domain model depend on a telemetry SDK.
type AppointmentTelemetry interface {
	StartScheduleAppointment(context.Context) (context.Context, func(outcome string))
	StartAppointmentTransition(context.Context, domain.AppointmentStatus, domain.AppointmentStatus) (context.Context, func(outcome string))
}

type noopAppointmentTelemetry struct{}

func (noopAppointmentTelemetry) StartScheduleAppointment(ctx context.Context) (context.Context, func(string)) {
	return ctx, func(string) {}
}

func (noopAppointmentTelemetry) StartAppointmentTransition(ctx context.Context, _, _ domain.AppointmentStatus) (context.Context, func(string)) {
	return ctx, func(string) {}
}

func appointmentOutcome(err error) string {
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
