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
	createErr            error
	hasFutureAppointment bool
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
