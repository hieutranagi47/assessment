package observability

import (
	"context"
	"time"

	"assessment/modules/appointment_scheduler/app"
	"assessment/modules/appointment_scheduler/domain"

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

func (t *AppointmentSchedulerTelemetry) StartScheduleAppointment(ctx context.Context) (context.Context, func(string)) {
	ctx, span := t.tracer.Start(ctx, "scheduler.schedule_appointment")
	started := time.Now()
	return ctx, func(outcome string) {
		attributes := metric.WithAttributes(attribute.String("outcome", outcome))
		t.bookingTotal.Add(ctx, 1, attributes)
		t.bookingDuration.Record(ctx, time.Since(started).Seconds(), attributes)
		span.SetAttributes(attribute.String("booking.outcome", outcome))
		if outcome == "error" {
			span.SetStatus(codes.Error, "booking failed")
		}
		span.End()
	}
}

func (t *AppointmentSchedulerTelemetry) StartAppointmentTransition(ctx context.Context, from, to domain.AppointmentStatus) (context.Context, func(string)) {
	ctx, span := t.tracer.Start(ctx, "scheduler.change_appointment_status")
	started := time.Now()
	return ctx, func(outcome string) {
		attributes := metric.WithAttributes(
			attribute.String("from", string(from)),
			attribute.String("to", string(to)),
			attribute.String("outcome", outcome),
		)
		t.transitionTotal.Add(ctx, 1, attributes)
		t.transitionDuration.Record(ctx, time.Since(started).Seconds(), attributes)
		span.SetAttributes(
			attribute.String("appointment.status.from", string(from)),
			attribute.String("appointment.status.to", string(to)),
			attribute.String("appointment.outcome", outcome),
		)
		if outcome == "error" {
			span.SetStatus(codes.Error, "appointment transition failed")
		}
		span.End()
	}
}
