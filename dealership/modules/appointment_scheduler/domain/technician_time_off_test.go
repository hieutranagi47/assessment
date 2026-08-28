package domain

import (
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestTechnicianTimeOffRejectsEmptyOrReversedIntervals(t *testing.T) {
	now := time.Date(2026, 8, 28, 2, 0, 0, 0, time.UTC)
	for _, interval := range [][2]time.Time{{now, now}, {now.Add(time.Hour), now}} {
		_, err := NewTechnicianTimeOff(uuid.New(), uuid.New(), uuid.New(), interval[0], interval[1], nil, now)
		if !errors.Is(err, ErrInvalidTimeOffInterval) {
			t.Fatalf("NewTechnicianTimeOff() error = %v, want ErrInvalidTimeOffInterval", err)
		}
	}
}

func TestTechnicianTimeOffNormalizesInstantsToUTC(t *testing.T) {
	now := time.Date(2026, 8, 28, 2, 0, 0, 0, time.FixedZone("UTC+7", 7*60*60))
	item, err := NewTechnicianTimeOff(uuid.New(), uuid.New(), uuid.New(), now, now.Add(time.Hour), nil, now)
	if err != nil {
		t.Fatalf("NewTechnicianTimeOff() error = %v", err)
	}
	if item.StartsAt().Location() != time.UTC || item.EndsAt().Location() != time.UTC {
		t.Fatal("time-off interval must be stored in UTC")
	}
}
