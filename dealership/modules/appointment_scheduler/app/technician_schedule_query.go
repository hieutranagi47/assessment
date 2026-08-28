package app

import (
	"context"
	"errors"
	"sort"
	"time"

	"assessment/modules/common"

	"github.com/google/uuid"
)

var ErrTechnicianScheduleDealershipNotFound = errors.New("technician schedule dealership not found")

// TechnicianScheduleRepository is the narrow read port for the dealership
// calendar. Its rows are purpose-built for this query and are not domain
// entities or HTTP response models.
type TechnicianScheduleRepository interface {
	CanReadTechnicianSchedules(context.Context, uuid.UUID, uuid.UUID) (bool, error)
	GetActiveTechnicianScheduleDealership(context.Context, uuid.UUID) (TechnicianScheduleDealership, error)
	ListActiveTechniciansForSchedule(context.Context, uuid.UUID, *uuid.UUID) ([]TechnicianScheduleTechnician, error)
	ListTechnicianScheduleShifts(context.Context, uuid.UUID, *uuid.UUID, int) ([]TechnicianScheduleShift, error)
	ListTechnicianScheduleAppointments(context.Context, uuid.UUID, *uuid.UUID, time.Time, time.Time) ([]TechnicianScheduleAppointment, error)
	ListTechnicianScheduleTimeOff(context.Context, uuid.UUID, *uuid.UUID, time.Time, time.Time) ([]TechnicianScheduleTimeOff, error)
}

type TechnicianScheduleDealership struct {
	ID       uuid.UUID
	Timezone string
}

type TechnicianScheduleTechnician struct {
	TechnicianID uuid.UUID
	UserID       uuid.UUID
	Name         string
}

type TechnicianScheduleShift struct {
	TechnicianID uuid.UUID
	StartsAt     time.Duration
	EndsAt       time.Duration
}

type TechnicianScheduleAppointment struct {
	TechnicianID    uuid.UUID
	AppointmentID   uuid.UUID
	ReferenceCode   string
	StartsAt        time.Time
	EndsAt          time.Time
	Status          string
	ServiceTypeName string
	ServiceBayID    uuid.UUID
	ServiceBayCode  string
}

type TechnicianScheduleTimeOff struct {
	TechnicianID uuid.UUID
	StartsAt     time.Time
	EndsAt       time.Time
}

type ListTechnicianSchedulesInput struct {
	ActorUserID  uuid.UUID
	DealershipID uuid.UUID
	Date         string
	TechnicianID *uuid.UUID
	Include      []string
}

type TechnicianScheduleResult struct {
	DealershipID   uuid.UUID
	Timezone       string
	Date           time.Time
	PeriodStartsAt time.Time
	PeriodEndsAt   time.Time
	Technicians    []TechnicianScheduleResultTechnician
}

type TechnicianScheduleResultTechnician struct {
	TechnicianID  uuid.UUID
	UserID        uuid.UUID
	Name          string
	Shifts        []TechnicianScheduleResultInterval
	OccupiedSlots []TechnicianScheduleResultOccupiedSlot
}

type TechnicianScheduleResultInterval struct {
	StartsAt time.Time
	EndsAt   time.Time
}

type TechnicianScheduleResultOccupiedSlot struct {
	Kind            string
	StartsAt        time.Time
	EndsAt          time.Time
	AppointmentID   *uuid.UUID
	ReferenceCode   *string
	Status          *string
	ServiceTypeName *string
	ServiceBayID    *uuid.UUID
	ServiceBayCode  *string
}

// TechnicianScheduleQuery returns one dealership's active technicians and
// their schedule records without performing availability calculations.
type TechnicianScheduleQuery struct {
	repository TechnicianScheduleRepository
}

func NewTechnicianScheduleQuery(repository TechnicianScheduleRepository) *TechnicianScheduleQuery {
	if repository == nil {
		panic("technician schedule query repository is required")
	}
	return &TechnicianScheduleQuery{repository: repository}
}

func (q *TechnicianScheduleQuery) List(ctx context.Context, input ListTechnicianSchedulesInput) (TechnicianScheduleResult, error) {
	if input.DealershipID == uuid.Nil {
		return TechnicianScheduleResult{}, common.NewInvalidInputError("invalid_dealership_id", "dealership ID is required")
	}
	if input.ActorUserID == uuid.Nil {
		return TechnicianScheduleResult{}, common.NewUnauthorizedError("authentication_required", "authentication is required")
	}

	date, err := time.Parse("2006-01-02", input.Date)
	if err != nil || date.Format("2006-01-02") != input.Date {
		return TechnicianScheduleResult{}, common.NewInvalidInputError("invalid_date", "date must use YYYY-MM-DD")
	}
	included, err := parseTechnicianScheduleIncludes(input.Include)
	if err != nil {
		return TechnicianScheduleResult{}, err
	}

	allowed, err := q.repository.CanReadTechnicianSchedules(ctx, input.ActorUserID, input.DealershipID)
	if err != nil {
		return TechnicianScheduleResult{}, err
	}
	if !allowed {
		return TechnicianScheduleResult{}, common.NewForbiddenError("technician_schedule_access_forbidden", "you are not allowed to view technician schedules for this dealership")
	}

	dealership, err := q.repository.GetActiveTechnicianScheduleDealership(ctx, input.DealershipID)
	if errors.Is(err, ErrTechnicianScheduleDealershipNotFound) {
		return TechnicianScheduleResult{}, common.NewNotFoundError("dealership_not_found", "dealership was not found")
	}
	if err != nil {
		return TechnicianScheduleResult{}, err
	}
	location, err := time.LoadLocation(dealership.Timezone)
	if err != nil {
		return TechnicianScheduleResult{}, err
	}

	localStart := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, location)
	localEnd := localStart.AddDate(0, 0, 1)
	periodStartsAt := localStart.UTC()
	periodEndsAt := localEnd.UTC()

	technicians, err := q.repository.ListActiveTechniciansForSchedule(ctx, dealership.ID, input.TechnicianID)
	if err != nil {
		return TechnicianScheduleResult{}, err
	}
	if input.TechnicianID != nil && len(technicians) == 0 {
		return TechnicianScheduleResult{}, common.NewNotFoundError("technician_not_found", "technician was not found")
	}

	result := TechnicianScheduleResult{
		DealershipID:   dealership.ID,
		Timezone:       dealership.Timezone,
		Date:           date,
		PeriodStartsAt: periodStartsAt,
		PeriodEndsAt:   periodEndsAt,
		Technicians:    make([]TechnicianScheduleResultTechnician, 0, len(technicians)),
	}
	byTechnicianID := make(map[uuid.UUID]*TechnicianScheduleResultTechnician, len(technicians))
	for _, technician := range technicians {
		result.Technicians = append(result.Technicians, TechnicianScheduleResultTechnician{
			TechnicianID:  technician.TechnicianID,
			UserID:        technician.UserID,
			Name:          technician.Name,
			Shifts:        make([]TechnicianScheduleResultInterval, 0),
			OccupiedSlots: make([]TechnicianScheduleResultOccupiedSlot, 0),
		})
		byTechnicianID[technician.TechnicianID] = &result.Technicians[len(result.Technicians)-1]
	}

	if included.shifts {
		if err := q.appendShifts(ctx, byTechnicianID, dealership.ID, input.TechnicianID, int(localStart.Weekday()), localStart, location); err != nil {
			return TechnicianScheduleResult{}, err
		}
	}
	if included.appointments {
		if err := q.appendAppointments(ctx, byTechnicianID, dealership.ID, input.TechnicianID, periodStartsAt, periodEndsAt); err != nil {
			return TechnicianScheduleResult{}, err
		}
	}
	if included.timeOff {
		if err := q.appendTimeOff(ctx, byTechnicianID, dealership.ID, input.TechnicianID, periodStartsAt, periodEndsAt); err != nil {
			return TechnicianScheduleResult{}, err
		}
	}
	for index := range result.Technicians {
		sort.Slice(result.Technicians[index].OccupiedSlots, func(left, right int) bool {
			leftSlot := result.Technicians[index].OccupiedSlots[left]
			rightSlot := result.Technicians[index].OccupiedSlots[right]
			if leftSlot.StartsAt.Equal(rightSlot.StartsAt) {
				return leftSlot.EndsAt.Before(rightSlot.EndsAt)
			}
			return leftSlot.StartsAt.Before(rightSlot.StartsAt)
		})
	}
	return result, nil
}

type technicianScheduleIncludes struct{ appointments, timeOff, shifts bool }

func parseTechnicianScheduleIncludes(values []string) (technicianScheduleIncludes, error) {
	if len(values) == 0 {
		return technicianScheduleIncludes{appointments: true, timeOff: true, shifts: true}, nil
	}
	includes := technicianScheduleIncludes{}
	for _, value := range values {
		switch value {
		case "appointments":
			includes.appointments = true
		case "time_off":
			includes.timeOff = true
		case "shifts":
			includes.shifts = true
		default:
			return technicianScheduleIncludes{}, common.NewInvalidInputError("invalid_include", "include contains an unsupported value")
		}
	}
	return includes, nil
}

func (q *TechnicianScheduleQuery) appendShifts(ctx context.Context, technicians map[uuid.UUID]*TechnicianScheduleResultTechnician, dealershipID uuid.UUID, technicianID *uuid.UUID, dayOfWeek int, date time.Time, location *time.Location) error {
	if dayOfWeek == 0 {
		dayOfWeek = 7
	}
	shifts, err := q.repository.ListTechnicianScheduleShifts(ctx, dealershipID, technicianID, dayOfWeek)
	if err != nil {
		return err
	}
	for _, shift := range shifts {
		technician := technicians[shift.TechnicianID]
		if technician == nil {
			continue
		}
		startsAt := localTimeOnDate(date, shift.StartsAt, location)
		endsAt := localTimeOnDate(date, shift.EndsAt, location)
		technician.Shifts = append(technician.Shifts, TechnicianScheduleResultInterval{StartsAt: startsAt.UTC(), EndsAt: endsAt.UTC()})
	}
	return nil
}

func localTimeOnDate(date time.Time, clock time.Duration, location *time.Location) time.Time {
	hours := int(clock / time.Hour)
	minutes := int(clock % time.Hour / time.Minute)
	seconds := int(clock % time.Minute / time.Second)
	nanoseconds := int(clock % time.Second)
	return time.Date(date.Year(), date.Month(), date.Day(), hours, minutes, seconds, nanoseconds, location)
}

func (q *TechnicianScheduleQuery) appendAppointments(ctx context.Context, technicians map[uuid.UUID]*TechnicianScheduleResultTechnician, dealershipID uuid.UUID, technicianID *uuid.UUID, periodStartsAt, periodEndsAt time.Time) error {
	appointments, err := q.repository.ListTechnicianScheduleAppointments(ctx, dealershipID, technicianID, periodStartsAt, periodEndsAt)
	if err != nil {
		return err
	}
	for _, appointment := range appointments {
		technician := technicians[appointment.TechnicianID]
		if technician == nil {
			continue
		}
		appointmentID := appointment.AppointmentID
		referenceCode := appointment.ReferenceCode
		status := appointment.Status
		serviceTypeName := appointment.ServiceTypeName
		serviceBayID := appointment.ServiceBayID
		serviceBayCode := appointment.ServiceBayCode
		technician.OccupiedSlots = append(technician.OccupiedSlots, TechnicianScheduleResultOccupiedSlot{Kind: "appointment", StartsAt: appointment.StartsAt.UTC(), EndsAt: appointment.EndsAt.UTC(), AppointmentID: &appointmentID, ReferenceCode: &referenceCode, Status: &status, ServiceTypeName: &serviceTypeName, ServiceBayID: &serviceBayID, ServiceBayCode: &serviceBayCode})
	}
	return nil
}

func (q *TechnicianScheduleQuery) appendTimeOff(ctx context.Context, technicians map[uuid.UUID]*TechnicianScheduleResultTechnician, dealershipID uuid.UUID, technicianID *uuid.UUID, periodStartsAt, periodEndsAt time.Time) error {
	timeOff, err := q.repository.ListTechnicianScheduleTimeOff(ctx, dealershipID, technicianID, periodStartsAt, periodEndsAt)
	if err != nil {
		return err
	}
	for _, item := range timeOff {
		technician := technicians[item.TechnicianID]
		if technician == nil {
			continue
		}
		technician.OccupiedSlots = append(technician.OccupiedSlots, TechnicianScheduleResultOccupiedSlot{Kind: "time_off", StartsAt: item.StartsAt.UTC(), EndsAt: item.EndsAt.UTC()})
	}
	return nil
}
