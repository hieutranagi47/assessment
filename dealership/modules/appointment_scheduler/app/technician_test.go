package app

import (
	"context"
	"testing"
	"time"

	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/auth/api/module/client"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

type technicianRepositoryStub struct {
	dealershipID         uuid.UUID
	technician           domain.Technician
	technicianSkill      domain.TechnicianSkill
	technicianShift      domain.TechnicianShift
	createErr            error
	skillCreateErr       error
	shiftCreateErr       error
	schedulerAdmin       bool
	hasFutureAppointment bool
	shiftInvalidates     bool
}

func (*technicianRepositoryStub) Create(context.Context, domain.Dealership) error { return nil }
func (r *technicianRepositoryStub) GetGlobalAdminDealership(context.Context, uuid.UUID) (uuid.UUID, error) {
	return r.dealershipID, nil
}
func (r *technicianRepositoryStub) CreateTechnician(_ context.Context, dealershipID uuid.UUID, technician domain.Technician) (domain.Technician, error) {
	if dealershipID != r.dealershipID {
		return domain.Technician{}, ErrTechnicianNotFound
	}
	if r.createErr != nil {
		return domain.Technician{}, r.createErr
	}
	r.technician = technician
	return technician, nil
}
func (r *technicianRepositoryStub) GetTechnician(_ context.Context, dealershipID, technicianID uuid.UUID) (domain.Technician, error) {
	if dealershipID != r.dealershipID || r.technician.ID() != technicianID {
		return domain.Technician{}, ErrTechnicianNotFound
	}
	return r.technician, nil
}
func (r *technicianRepositoryStub) ListTechnicians(context.Context, uuid.UUID, *bool, int, int) ([]domain.Technician, error) {
	return []domain.Technician{r.technician}, nil
}
func (r *technicianRepositoryStub) UpdateTechnician(_ context.Context, _ uuid.UUID, technician domain.Technician) (domain.Technician, error) {
	r.technician = technician
	return technician, nil
}
func (r *technicianRepositoryStub) HasFutureActiveTechnicianAppointments(context.Context, uuid.UUID, time.Time) (bool, error) {
	return r.hasFutureAppointment, nil
}
func (r *technicianRepositoryStub) DeactivateTechnician(_ context.Context, _ uuid.UUID, _ uuid.UUID, _ time.Time) error {
	return nil
}
func (r *technicianRepositoryStub) IsActiveSchedulerAdmin(context.Context, uuid.UUID) (bool, error) {
	return r.schedulerAdmin, nil
}
func (r *technicianRepositoryStub) CreateTechnicianSkill(_ context.Context, skill domain.TechnicianSkill) (domain.TechnicianSkill, error) {
	if r.skillCreateErr != nil {
		return domain.TechnicianSkill{}, r.skillCreateErr
	}
	r.technicianSkill = skill
	return skill, nil
}
func (r *technicianRepositoryStub) GetTechnicianSkill(_ context.Context, technicianID, skillID uuid.UUID) (domain.TechnicianSkill, error) {
	if r.technicianSkill.ID() != skillID || r.technicianSkill.TechnicianID() != technicianID {
		return domain.TechnicianSkill{}, ErrTechnicianSkillNotFound
	}
	return r.technicianSkill, nil
}
func (r *technicianRepositoryStub) ListTechnicianSkills(_ context.Context, technicianID uuid.UUID) ([]domain.TechnicianSkill, error) {
	if r.technicianSkill.TechnicianID() != technicianID {
		return nil, ErrTechnicianNotFound
	}
	return []domain.TechnicianSkill{r.technicianSkill}, nil
}
func (r *technicianRepositoryStub) UpdateTechnicianSkill(_ context.Context, skill domain.TechnicianSkill) (domain.TechnicianSkill, error) {
	r.technicianSkill = skill
	return skill, nil
}
func (r *technicianRepositoryStub) DeleteTechnicianSkill(_ context.Context, technicianID, skillID uuid.UUID) error {
	if r.technicianSkill.ID() != skillID || r.technicianSkill.TechnicianID() != technicianID {
		return ErrTechnicianSkillNotFound
	}
	r.technicianSkill = domain.TechnicianSkill{}
	return nil
}

func (r *technicianRepositoryStub) CreateTechnicianShift(_ context.Context, shift domain.TechnicianShift) error {
	if r.shiftCreateErr != nil {
		return r.shiftCreateErr
	}
	r.technicianShift = shift
	return nil
}

func (r *technicianRepositoryStub) GetTechnicianShift(_ context.Context, dealershipID, technicianID, shiftID uuid.UUID) (domain.TechnicianShift, error) {
	if dealershipID != r.dealershipID || r.technicianShift.ID() != shiftID || r.technicianShift.TechnicianID() != technicianID {
		return domain.TechnicianShift{}, ErrTechnicianShiftNotFound
	}
	return r.technicianShift, nil
}

func (r *technicianRepositoryStub) ListTechnicianShifts(_ context.Context, dealershipID, technicianID uuid.UUID) ([]domain.TechnicianShift, error) {
	if dealershipID != r.dealershipID || r.technician.ID() != technicianID {
		return nil, ErrTechnicianNotFound
	}
	if r.technicianShift.ID() == uuid.Nil {
		return []domain.TechnicianShift{}, nil
	}
	return []domain.TechnicianShift{r.technicianShift}, nil
}

func (r *technicianRepositoryStub) UpdateTechnicianShift(_ context.Context, dealershipID uuid.UUID, shift domain.TechnicianShift) error {
	if dealershipID != r.dealershipID || r.technicianShift.ID() != shift.ID() {
		return ErrTechnicianShiftNotFound
	}
	r.technicianShift = shift
	return nil
}

func (r *technicianRepositoryStub) DeleteTechnicianShift(_ context.Context, dealershipID, technicianID, shiftID uuid.UUID, _ time.Time) error {
	if dealershipID != r.dealershipID || r.technicianShift.ID() != shiftID || r.technicianShift.TechnicianID() != technicianID {
		return ErrTechnicianShiftNotFound
	}
	r.technicianShift = domain.TechnicianShift{}
	return nil
}

func (r *technicianRepositoryStub) HasFutureAppointmentsOutsideTechnicianShift(_ context.Context, _ uuid.UUID, _ domain.TechnicianShift, _ uuid.UUID, _ time.Time) (bool, error) {
	return r.shiftInvalidates, nil
}

func TestTechnicianAuthorizationValidationDuplicatesAndFutureAppointments(t *testing.T) {
	actor, dealershipID := uuid.New(), uuid.New()
	admin := userInfoStub{info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}}
	newService := func(repository *technicianRepositoryStub, user userInfoStub) *Service {
		service := NewService(repository, user)
		service.newID = uuid.New
		return service
	}

	t.Run("non admins are denied", func(t *testing.T) {
		service := newService(&technicianRepositoryStub{dealershipID: dealershipID}, userInfoStub{info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "staff"}})
		_, err := service.CreateTechnician(context.Background(), actor, CreateTechnicianInput{Name: "Ada", Phone: "+84901234567", IsActive: true})
		require.ErrorContains(t, err, "technician_access_forbidden")
	})

	t.Run("phone is normalized and email duplicates conflict", func(t *testing.T) {
		repository := &technicianRepositoryStub{dealershipID: dealershipID}
		service := newService(repository, admin)
		created, err := service.CreateTechnician(context.Background(), actor, CreateTechnicianInput{Name: " Ada ", Phone: "00 84-901-234-567", IsActive: true})
		require.NoError(t, err)
		require.Equal(t, "+84901234567", created.Phone())
		repository.createErr = ErrTechnicianEmailTaken
		email := "ada@example.com"
		_, err = service.CreateTechnician(context.Background(), actor, CreateTechnicianInput{Name: "Ada", Phone: "+84909999999", Email: &email, IsActive: true})
		require.ErrorContains(t, err, "technician_email_taken")
	})

	t.Run("future active appointments block deactivation", func(t *testing.T) {
		repository := &technicianRepositoryStub{dealershipID: dealershipID, hasFutureAppointment: true}
		service := newService(repository, admin)
		created, err := service.CreateTechnician(context.Background(), actor, CreateTechnicianInput{Name: "Ada", Phone: "+84901234567", IsActive: true})
		require.NoError(t, err)
		err = service.DeactivateTechnician(context.Background(), actor, created.ID())
		require.ErrorContains(t, err, "technician_future_active_appointments")
	})
}

func TestTechnicianSkillsAuthorizationOwnershipAndMutations(t *testing.T) {
	actor, technicianID, firstSkillID, secondSkillID := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	repository := &technicianRepositoryStub{schedulerAdmin: true}
	service := NewService(repository, userInfoStub{})
	service.newID = uuid.New

	t.Run("unauthenticated actors are rejected", func(t *testing.T) {
		_, err := service.CreateTechnicianSkill(context.Background(), uuid.Nil, technicianID, CreateTechnicianSkillInput{SkillID: firstSkillID})
		require.ErrorContains(t, err, "authentication_required")
	})

	t.Run("non-admins are rejected", func(t *testing.T) {
		repository.schedulerAdmin = false
		_, err := service.CreateTechnicianSkill(context.Background(), actor, technicianID, CreateTechnicianSkillInput{SkillID: firstSkillID})
		require.ErrorContains(t, err, "technician_skill_access_forbidden")
		repository.schedulerAdmin = true
	})

	t.Run("duplicate assignments conflict", func(t *testing.T) {
		repository.skillCreateErr = ErrTechnicianSkillTaken
		_, err := service.CreateTechnicianSkill(context.Background(), actor, technicianID, CreateTechnicianSkillInput{SkillID: firstSkillID})
		require.ErrorContains(t, err, "technician_skill_taken")
		repository.skillCreateErr = nil
	})

	created, err := service.CreateTechnicianSkill(context.Background(), actor, technicianID, CreateTechnicianSkillInput{SkillID: firstSkillID})
	require.NoError(t, err)

	t.Run("ownership mismatch is not found", func(t *testing.T) {
		_, err := service.UpdateTechnicianSkill(context.Background(), actor, uuid.New(), created.ID(), UpdateTechnicianSkillInput{SkillID: &secondSkillID})
		require.ErrorContains(t, err, "technician_skill_not_found")
	})

	t.Run("update, list, and delete succeed", func(t *testing.T) {
		updated, err := service.UpdateTechnicianSkill(context.Background(), actor, technicianID, created.ID(), UpdateTechnicianSkillInput{SkillID: &secondSkillID})
		require.NoError(t, err)
		require.Equal(t, secondSkillID, updated.SkillID())
		items, err := service.ListTechnicianSkills(context.Background(), actor, technicianID)
		require.NoError(t, err)
		require.Len(t, items, 1)
		require.NoError(t, service.DeleteTechnicianSkill(context.Background(), actor, technicianID, created.ID()))
		err = service.DeleteTechnicianSkill(context.Background(), actor, technicianID, created.ID())
		require.ErrorContains(t, err, "technician_skill_not_found")
	})
}

func TestTechnicianShiftsAuthorizationValidationAndAppointmentProtection(t *testing.T) {
	actor, dealershipID := uuid.New(), uuid.New()
	technician, err := domain.NewTechnician(uuid.New(), uuid.New(), "Ada", "+84901234567", nil, true, time.Now())
	require.NoError(t, err)
	repository := &technicianRepositoryStub{dealershipID: dealershipID, technician: technician}
	admin := userInfoStub{info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "admin"}}
	service := NewService(repository, admin)
	service.newID = uuid.New

	_, err = service.CreateTechnicianShift(context.Background(), uuid.Nil, technician.ID(), CreateTechnicianShiftInput{DayOfWeek: 1, StartsAt: 8 * time.Hour, EndsAt: 17 * time.Hour})
	require.ErrorContains(t, err, "unauthenticated")

	service.users = userInfoStub{info: client.UserInfo{UserID: actor.String(), Status: "active", Role: "staff"}}
	_, err = service.CreateTechnicianShift(context.Background(), actor, technician.ID(), CreateTechnicianShiftInput{DayOfWeek: 1, StartsAt: 8 * time.Hour, EndsAt: 17 * time.Hour})
	require.ErrorContains(t, err, "forbidden")
	service.users = admin

	_, err = service.CreateTechnicianShift(context.Background(), actor, technician.ID(), CreateTechnicianShiftInput{DayOfWeek: 1, StartsAt: 17 * time.Hour, EndsAt: 8 * time.Hour})
	require.ErrorContains(t, err, "validation_failed")

	created, err := service.CreateTechnicianShift(context.Background(), actor, technician.ID(), CreateTechnicianShiftInput{DayOfWeek: 1, StartsAt: 8 * time.Hour, EndsAt: 17 * time.Hour})
	require.NoError(t, err)
	require.Equal(t, technician.ID(), created.TechnicianID())

	repository.shiftCreateErr = ErrTechnicianShiftOverlaps
	_, err = service.CreateTechnicianShift(context.Background(), actor, technician.ID(), CreateTechnicianShiftInput{DayOfWeek: 1, StartsAt: 9 * time.Hour, EndsAt: 10 * time.Hour})
	require.ErrorContains(t, err, "shift_overlap")
	repository.shiftCreateErr = nil

	repository.shiftInvalidates = true
	_, err = service.UpdateTechnicianShift(context.Background(), actor, technician.ID(), created.ID(), UpdateTechnicianShiftInput{})
	require.ErrorContains(t, err, "appointment_schedule_conflict")
	err = service.DeleteTechnicianShift(context.Background(), actor, technician.ID(), created.ID())
	require.ErrorContains(t, err, "appointment_schedule_conflict")
}
