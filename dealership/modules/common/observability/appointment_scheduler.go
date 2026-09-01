package observability

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"assessment/modules/appointment_scheduler/app"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/trace"
)

// AppointmentSchedulerTelemetry provides low-cardinality business metrics and
// application spans for appointment use cases.
type AppointmentSchedulerTelemetry struct {
	tracer             trace.Tracer
	bookingTotal       metric.Int64Counter
	bookingDuration    metric.Float64Histogram
	transitionTotal    metric.Int64Counter
	transitionDuration metric.Float64Histogram
}

var _ app.AppointmentTelemetry = (*AppointmentSchedulerTelemetry)(nil)

func NewAppointmentSchedulerTelemetry() (*AppointmentSchedulerTelemetry, error) {
	meter := otel.Meter("assessment/appointment_scheduler")
	bookingTotal, err := meter.Int64Counter("appointment_booking_total")
	if err != nil {
		return nil, err
	}
	bookingDuration, err := meter.Float64Histogram("appointment_booking_duration_seconds", metric.WithUnit("s"))
	if err != nil {
		return nil, err
	}
	transitionTotal, err := meter.Int64Counter("appointment_lifecycle_transition_total")
	if err != nil {
		return nil, err
	}
	transitionDuration, err := meter.Float64Histogram("appointment_lifecycle_transition_duration_seconds", metric.WithUnit("s"))
	if err != nil {
		return nil, err
	}
	return &AppointmentSchedulerTelemetry{
		tracer:             otel.Tracer("assessment/appointment_scheduler"),
		bookingTotal:       bookingTotal,
		bookingDuration:    bookingDuration,
		transitionTotal:    transitionTotal,
		transitionDuration: transitionDuration,
	}, nil
}

func (t *AppointmentSchedulerTelemetry) StartScheduleAppointment(ctx context.Context, metadata app.ScheduleAppointmentTraceMetadata) (context.Context, func(app.ScheduleAppointmentTraceResult, error)) {
	ctx, span := t.tracer.Start(ctx, "scheduler.schedule_appointment")
	span.SetAttributes(
		attribute.String("actor.id", metadata.ActorID.String()),
		attribute.String("customer.id", metadata.CustomerID.String()),
		attribute.String("vehicle.id", metadata.VehicleID.String()),
		attribute.String("service_type.id", metadata.ServiceTypeID.String()),
		attribute.String("technician.id", metadata.TechnicianID.String()),
		attribute.String("service_bay.id", metadata.ServiceBayID.String()),
	)
	started := time.Now()
	return ctx, func(result app.ScheduleAppointmentTraceResult, err error) {
		outcome := app.AppointmentOutcome(err)
		attributes := metric.WithAttributes(attribute.String("outcome", outcome))
		t.bookingTotal.Add(ctx, 1, attributes)
		t.bookingDuration.Record(ctx, time.Since(started).Seconds(), attributes)
		span.SetAttributes(
			attribute.String("booking.outcome", outcome),
			attribute.Int("status_code", app.AppointmentStatusCode(err, http.StatusCreated)),
		)
		if err != nil {
			recordSpanError(span, err, "booking failed")
		} else {
			span.SetAttributes(
				attribute.Int("record_count", 1),
				attribute.String("appointment.id", result.AppointmentID.String()),
				attribute.String("dealership.id", result.DealershipID.String()),
			)
		}
		span.End()
	}
}

func (t *AppointmentSchedulerTelemetry) StartAppointmentTransition(ctx context.Context, metadata app.AppointmentTransitionTraceMetadata) (context.Context, func(error)) {
	ctx, span := t.tracer.Start(ctx, "scheduler.change_appointment_status")
	span.SetAttributes(
		attribute.String("actor.id", metadata.ActorID.String()),
		attribute.String("appointment.id", metadata.AppointmentID.String()),
	)
	started := time.Now()
	return ctx, func(err error) {
		outcome := app.AppointmentOutcome(err)
		attributes := metric.WithAttributes(
			attribute.String("from", string(metadata.From)),
			attribute.String("to", string(metadata.To)),
			attribute.String("outcome", outcome),
		)
		t.transitionTotal.Add(ctx, 1, attributes)
		t.transitionDuration.Record(ctx, time.Since(started).Seconds(), attributes)
		span.SetAttributes(
			attribute.String("appointment.status.from", string(metadata.From)),
			attribute.String("appointment.status.to", string(metadata.To)),
			attribute.String("appointment.outcome", outcome),
			attribute.Int("status_code", app.AppointmentStatusCode(err, http.StatusNoContent)),
		)
		if err != nil {
			recordSpanError(span, err, "appointment transition failed")
		} else {
			span.SetAttributes(attribute.Int("record_count", 1))
		}
		span.End()
	}
}

func recordSpanError(span trace.Span, err error, statusDescription string) {
	span.SetStatus(codes.Error, statusDescription)
	span.SetAttributes(attribute.String("error.type", fmt.Sprintf("%T", err)))
	span.RecordError(err)
}
