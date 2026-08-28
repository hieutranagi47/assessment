package app

import (
	"testing"

	"assessment/modules/appointment_scheduler/domain"
)

func TestValidAppointmentTransition(t *testing.T) {
	testCases := []struct {
		from domain.AppointmentStatus
		to   domain.AppointmentStatus
		want bool
	}{
		{domain.AppointmentRequested, domain.AppointmentCheckedIn, true},
		{domain.AppointmentCheckedIn, domain.AppointmentInProgress, true},
		{domain.AppointmentInProgress, domain.AppointmentCompleted, true},
		{domain.AppointmentRequested, domain.AppointmentCancelled, true},
		{domain.AppointmentCompleted, domain.AppointmentCancelled, false},
		{domain.AppointmentRequested, domain.AppointmentCompleted, false},
	}

	for _, testCase := range testCases {
		name := string(testCase.from) + "_to_" + string(testCase.to)
		t.Run(name, func(t *testing.T) {
			if got := validAppointmentTransition(testCase.from, testCase.to); got != testCase.want {
				t.Fatalf("validAppointmentTransition() = %v, want %v", got, testCase.want)
			}
		})
	}
}
