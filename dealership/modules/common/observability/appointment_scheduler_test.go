package observability

import (
	"context"
	"testing"

	"assessment/modules/appointment_scheduler/domain"

	"github.com/stretchr/testify/require"
)

func TestAppointmentSchedulerTelemetryRecordsScheduleAndTransitionOutcomes(t *testing.T) {
	telemetry, err := NewAppointmentSchedulerTelemetry()
	require.NoError(t, err)

	ctx, finishSchedule := telemetry.StartScheduleAppointment(context.Background())
	require.NotNil(t, ctx)
	finishSchedule("success")

	ctx, finishTransition := telemetry.StartAppointmentTransition(ctx, domain.AppointmentRequested, domain.AppointmentCompleted)
	require.NotNil(t, ctx)
	finishTransition("error")
}
