package db

import (
	"context"
	"errors"
	"time"

	"assessment/modules/appointment_scheduler/adapters/db/dbmodels"
	"assessment/modules/appointment_scheduler/app"
	"assessment/modules/appointment_scheduler/domain"
	"assessment/modules/common"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func (r *DealershipRepository) GetGlobalAdminDealership(ctx context.Context, authUserID uuid.UUID) (uuid.UUID, error) {
	dealershipID, err := r.queries.GetGlobalAdminDealership(ctx, toPGUUID(authUserID))
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, app.ErrTechnicianNotFound
	}
	if err != nil {
		return uuid.Nil, err
	}
	return fromPGUUID(dealershipID), nil
}

func (r *DealershipRepository) CreateTechnician(
	ctx context.Context,
	dealershipID uuid.UUID,
	technician domain.Technician,
) (domain.Technician, error) {
	// The generated CTE inserts both records as one PostgreSQL statement, so a
	// failed technician insert rolls back the employee user insert atomically.
	phone := technician.Phone()
	row, err := r.queries.CreateTechnician(ctx, dbmodels.CreateTechnicianParams{
		UserID:       toPGUUID(technician.UserID()),
		Name:         technician.Name(),
		Phone:        &phone,
		Email:        technician.Email(),
		DealershipID: toPGUUID(dealershipID),
		IsActive:     technician.IsActive(),
		CreatedAt:    technician.CreatedAt(),
		UpdatedAt:    technician.UpdatedAt(),
		TechnicianID: toPGUUID(technician.ID()),
	})
	return technicianFromRow(
		row.TechnicianID, row.UserID, row.Name, row.Phone, row.Email,
		row.IsActive, row.CreatedAt, row.UpdatedAt, err,
	)
}

func (r *DealershipRepository) GetTechnician(ctx context.Context, dealershipID, technicianID uuid.UUID) (domain.Technician, error) {
	row, err := r.queries.GetTechnicianForDealership(ctx, dbmodels.GetTechnicianForDealershipParams{
		TechnicianID: toPGUUID(technicianID),
		DealershipID: toPGUUID(dealershipID),
	})
	return technicianFromRow(row.TechnicianID, row.UserID, row.Name, row.Phone, row.Email, row.IsActive, row.CreatedAt, row.UpdatedAt, err)
}

func (r *DealershipRepository) ListTechnicians(ctx context.Context, dealershipID uuid.UUID, isActive *bool, limit, offset int) ([]domain.Technician, error) {
	rows, err := r.queries.ListTechniciansForDealership(ctx, dbmodels.ListTechniciansForDealershipParams{
		DealershipID: toPGUUID(dealershipID),
		IsActive:     isActive,
		Limit:        int32(limit),
		Offset:       int32(offset),
	})
	if err != nil {
		return nil, err
	}
	items := make([]domain.Technician, 0, len(rows))
	for _, row := range rows {
		technician, err := technicianFromRow(
			row.TechnicianID, row.UserID, row.Name, row.Phone, row.Email,
			row.IsActive, row.CreatedAt, row.UpdatedAt, nil,
		)
		if err != nil {
			return nil, err
		}
		items = append(items, technician)
	}
	return items, nil
}

func (r *DealershipRepository) UpdateTechnician(ctx context.Context, dealershipID uuid.UUID, technician domain.Technician) (domain.Technician, error) {
	phone := technician.Phone()
	row, err := r.queries.UpdateTechnicianForDealership(ctx, dbmodels.UpdateTechnicianForDealershipParams{
		Name:         technician.Name(),
		Phone:        &phone,
		Email:        technician.Email(),
		IsActive:     technician.IsActive(),
		UpdatedAt:    technician.UpdatedAt(),
		TechnicianID: toPGUUID(technician.ID()),
		DealershipID: toPGUUID(dealershipID),
	})
	return technicianFromRow(row.TechnicianID, row.UserID, row.Name, row.Phone, row.Email, row.IsActive, row.CreatedAt, row.UpdatedAt, err)
}

func (r *DealershipRepository) HasFutureActiveTechnicianAppointments(ctx context.Context, technicianID uuid.UUID, now time.Time) (bool, error) {
	return r.queries.HasFutureActiveTechnicianAppointments(ctx, dbmodels.HasFutureActiveTechnicianAppointmentsParams{
		TechnicianID: toPGUUID(technicianID),
		Now:          now,
	})
}

func (r *DealershipRepository) DeactivateTechnician(ctx context.Context, dealershipID, technicianID uuid.UUID, now time.Time) error {
	rows, err := r.queries.DeactivateTechnicianForDealership(ctx, dbmodels.DeactivateTechnicianForDealershipParams{
		UpdatedAt:    now,
		TechnicianID: toPGUUID(technicianID),
		DealershipID: toPGUUID(dealershipID),
	})
	if err != nil {
		return err
	}
	if rows == 0 {
		return app.ErrTechnicianNotFound
	}
	return nil
}

func technicianFromRow(technicianID, userID pgtype.UUID, name string, phone, email *string, isActive bool, createdAt, updatedAt time.Time, err error) (domain.Technician, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Technician{}, app.ErrTechnicianNotFound
	}
	if err != nil {
		if common.IsUniqueViolationError(err, "technicians_dealership_phone_unique") {
			return domain.Technician{}, app.ErrTechnicianPhoneTaken
		}
		if common.IsUniqueViolationError(err, "technicians_dealership_email_unique") {
			return domain.Technician{}, app.ErrTechnicianEmailTaken
		}
		return domain.Technician{}, err
	}
	if phone == nil {
		return domain.Technician{}, errors.New("technician phone is unexpectedly null")
	}
	return domain.RehydrateTechnician(fromPGUUID(technicianID), fromPGUUID(userID), name, *phone, email, isActive, createdAt, updatedAt)
}
