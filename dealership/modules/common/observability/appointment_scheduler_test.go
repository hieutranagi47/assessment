package observability

import (
	"context"
	"testing"

	"assessment/modules/appointment_scheduler/app"
	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	tracesdk "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
)

func TestAppointmentSchedulerTelemetryRecordsOnlySummaryMetadataOnSuccess(t *testing.T) {
	recorder := tracetest.NewSpanRecorder()
	provider := tracesdk.NewTracerProvider(tracesdk.WithSpanProcessor(recorder))
	previousProvider := otel.GetTracerProvider()
	otel.SetTracerProvider(provider)
	t.Cleanup(func() {
		otel.SetTracerProvider(previousProvider)
		require.NoError(t, provider.Shutdown(context.Background()))
	})

	telemetry, err := NewAppointmentSchedulerTelemetry()
	require.NoError(t, err)

	appointmentID := uuid.New()
	dealershipID := uuid.New()
	ctx, finishSchedule := telemetry.StartScheduleAppointment(context.Background(), app.ScheduleAppointmentTraceMetadata{
		ActorID:       uuid.New(),
		CustomerID:    uuid.New(),
		VehicleID:     uuid.New(),
		ServiceTypeID: uuid.New(),
		TechnicianID:  uuid.New(),
		ServiceBayID:  uuid.New(),
	})
	require.NotNil(t, ctx)
	finishSchedule(app.ScheduleAppointmentTraceResult{AppointmentID: appointmentID, DealershipID: dealershipID}, nil)

	spans := recorder.Ended()
	require.Len(t, spans, 1)
	span := spans[0]
	require.Equal(t, codes.Unset, span.Status().Code)
	require.Equal(t, int64(201), traceAttribute(span, "status_code").AsInt64())
	require.Equal(t, int64(1), traceAttribute(span, "record_count").AsInt64())
	require.Equal(t, appointmentID.String(), traceAttribute(span, "appointment.id").AsString())
	require.Equal(t, dealershipID.String(), traceAttribute(span, "dealership.id").AsString())
	require.Empty(t, span.Events())
}

func TestAppointmentSchedulerTelemetryRecordsErrorDetailsOnlyOnFailure(t *testing.T) {
	recorder := tracetest.NewSpanRecorder()
	provider := tracesdk.NewTracerProvider(tracesdk.WithSpanProcessor(recorder))
	previousProvider := otel.GetTracerProvider()
	otel.SetTracerProvider(provider)
	t.Cleanup(func() {
		otel.SetTracerProvider(previousProvider)
		require.NoError(t, provider.Shutdown(context.Background()))
	})

	telemetry, err := NewAppointmentSchedulerTelemetry()
	require.NoError(t, err)

	_, finishTransition := telemetry.StartAppointmentTransition(context.Background(), app.AppointmentTransitionTraceMetadata{
		ActorID:       uuid.New(),
		AppointmentID: uuid.New(),
		From:          domain.AppointmentRequested,
		To:            domain.AppointmentCompleted,
	})
	finishTransition(common.NewConflictError("availability_conflict", "the selected technician is unavailable"))

	spans := recorder.Ended()
	require.Len(t, spans, 1)
	span := spans[0]
	require.Equal(t, codes.Error, span.Status().Code)
	require.Equal(t, int64(409), traceAttribute(span, "status_code").AsInt64())
	require.NotEmpty(t, traceAttribute(span, "error.type").AsString())
	require.Len(t, span.Events(), 1)
	require.Equal(t, "exception", span.Events()[0].Name)
}

func traceAttribute(span tracesdk.ReadOnlySpan, key string) attribute.Value {
	for _, current := range span.Attributes() {
		if string(current.Key) == key {
			return current.Value
		}
	}
	return attribute.Value{}
}
