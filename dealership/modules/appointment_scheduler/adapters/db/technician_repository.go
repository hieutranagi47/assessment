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
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
)

func (r *DealershipRepository) GetEmployeeDealership(ctx context.Context, authUserID uuid.UUID) (uuid.UUID, error) {
	dealershipID, err := r.queries.GetActiveSchedulerEmployeeDealership(ctx, toPGUUID(authUserID))
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, app.ErrTechnicianNotFound
	}
	return fromPGUUID(dealershipID), err
}

func (r *DealershipRepository) GetSchedulerUserID(ctx context.Context, authUserID uuid.UUID) (uuid.UUID, error) {
	userID, err := r.queries.GetActiveSchedulerEmployeeID(ctx, toPGUUID(authUserID))
	if errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, app.ErrTechnicianNotFound
	}
	return fromPGUUID(userID), err
}

func (r *DealershipRepository) CreateTechnicianTimeOff(ctx context.Context, item domain.TechnicianTimeOff) error {
	return r.withTechnicianScheduleLock(ctx, item.TechnicianID(), func(tx pgx.Tx, queries *dbmodels.Queries) error {
		conflict, err := hasActiveAppointmentOverlap(ctx, tx, item.TechnicianID(), item.StartsAt(), item.EndsAt())
		if err != nil {
			return err
		}
		if conflict {
			return app.ErrTechnicianTimeOffAppointmentConflict
		}
		err = queries.CreateTechnicianTimeOff(ctx, dbmodels.CreateTechnicianTimeOffParams{TechnicianTimeOffID: toPGUUID(item.ID()), TechnicianID: toPGUUID(item.TechnicianID()), StartsAt: item.StartsAt(), EndsAt: item.EndsAt(), Reason: item.Reason(), CreatedByUserID: toPGUUID(item.CreatedByUserID()), CreatedAt: item.CreatedAt(), UpdatedAt: item.UpdatedAt()})
		return technicianTimeOffWriteError(err)
	})
}

func (r *DealershipRepository) GetTechnicianTimeOff(ctx context.Context, technicianID, timeOffID uuid.UUID) (domain.TechnicianTimeOff, error) {
	row, err := r.queries.GetTechnicianTimeOff(ctx, dbmodels.GetTechnicianTimeOffParams{TechnicianTimeOffID: toPGUUID(timeOffID), TechnicianID: toPGUUID(technicianID)})
	return technicianTimeOffFromValues(row.TechnicianTimeOffID, row.TechnicianID, row.CreatedByUserID, row.StartsAt, row.EndsAt, row.Reason, row.CreatedAt, row.UpdatedAt, err)
}

func (r *DealershipRepository) ListTechnicianTimeOff(ctx context.Context, technicianID uuid.UUID, from, to *time.Time, limit, offset int) ([]domain.TechnicianTimeOff, error) {
	if from == nil {
		value := time.Now().UTC()
		from = &value
	}
	var fromAt, toAt pgtype.Timestamptz
	if from != nil {
		fromAt = pgtype.Timestamptz{Time: from.UTC(), Valid: true}
	}
	if to != nil {
		toAt = pgtype.Timestamptz{Time: to.UTC(), Valid: true}
	}
	rows, err := r.queries.ListTechnicianTimeOff(ctx, dbmodels.ListTechnicianTimeOffParams{TechnicianID: toPGUUID(technicianID), FromAt: fromAt, ToAt: toAt, Limit: int32(limit), Offset: int32(offset)})
	if err != nil {
		return nil, err
	}
	items := make([]domain.TechnicianTimeOff, 0, len(rows))
	for _, row := range rows {
		item, err := technicianTimeOffFromValues(row.TechnicianTimeOffID, row.TechnicianID, row.CreatedByUserID, row.StartsAt, row.EndsAt, row.Reason, row.CreatedAt, row.UpdatedAt, nil)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, nil
}

func (r *DealershipRepository) UpdateTechnicianTimeOff(ctx context.Context, item domain.TechnicianTimeOff) error {
	return r.withTechnicianScheduleLock(ctx, item.TechnicianID(), func(tx pgx.Tx, queries *dbmodels.Queries) error {
		conflict, err := hasActiveAppointmentOverlap(ctx, tx, item.TechnicianID(), item.StartsAt(), item.EndsAt())
		if err != nil {
			return err
		}
		if conflict {
			return app.ErrTechnicianTimeOffAppointmentConflict
		}
		rows, err := queries.UpdateTechnicianTimeOff(ctx, dbmodels.UpdateTechnicianTimeOffParams{TechnicianTimeOffID: toPGUUID(item.ID()), TechnicianID: toPGUUID(item.TechnicianID()), StartsAt: item.StartsAt(), EndsAt: item.EndsAt(), Reason: item.Reason(), UpdatedAt: item.UpdatedAt()})
		if err = technicianTimeOffWriteError(err); err != nil {
			return err
		}
		if rows == 0 {
			return app.ErrTechnicianTimeOffNotFound
		}
		return nil
	})
}

func (r *DealershipRepository) DeleteTechnicianTimeOff(ctx context.Context, technicianID, timeOffID uuid.UUID, now time.Time) error {
	rows, err := r.queries.DeleteTechnicianTimeOff(ctx, dbmodels.DeleteTechnicianTimeOffParams{DeletedAt: now.UTC(), TechnicianTimeOffID: toPGUUID(timeOffID), TechnicianID: toPGUUID(technicianID)})
	if err != nil {
		return err
	}
	if rows == 0 {
		return app.ErrTechnicianTimeOffNotFound
	}
	return nil
}

func (r *DealershipRepository) withTechnicianScheduleLock(ctx context.Context, technicianID uuid.UUID, write func(pgx.Tx, *dbmodels.Queries) error) error {
	tx, err := r.database.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))", technicianID.String()); err != nil {
		return err
	}
	if err := write(tx, r.queries.WithTx(tx)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func hasActiveAppointmentOverlap(ctx context.Context, tx pgx.Tx, technicianID uuid.UUID, startsAt, endsAt time.Time) (bool, error) {
	var conflict bool
	err := tx.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM appointment_scheduler.appointments WHERE technician_id = $1 AND deleted_at IS NULL AND status IN ('requested', 'checked_in', 'in_progress') AND starts_at < $3 AND ends_at > $2)", toPGUUID(technicianID), startsAt.UTC(), endsAt.UTC()).Scan(&conflict)
	return conflict, err
}

func technicianTimeOffFromValues(id, technicianID, createdByUserID pgtype.UUID, startsAt, endsAt time.Time, reason *string, createdAt, updatedAt time.Time, err error) (domain.TechnicianTimeOff, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.TechnicianTimeOff{}, app.ErrTechnicianTimeOffNotFound
	}
	if err != nil {
		return domain.TechnicianTimeOff{}, err
	}
	return domain.RehydrateTechnicianTimeOff(fromPGUUID(id), fromPGUUID(technicianID), fromPGUUID(createdByUserID), startsAt, endsAt, reason, createdAt, updatedAt)
}

func technicianTimeOffWriteError(err error) error {
	var postgresErr *pgconn.PgError
	if errors.As(err, &postgresErr) && postgresErr.Code == "23P01" && postgresErr.ConstraintName == "technician_time_off_no_overlap" {
		return app.ErrTechnicianTimeOffOverlaps
	}
	return err
}

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

func (r *DealershipRepository) CreateTechnicianShift(ctx context.Context, shift domain.TechnicianShift) error {
	err := r.queries.CreateTechnicianShift(ctx, dbmodels.CreateTechnicianShiftParams{
		TechnicianShiftID: toPGUUID(shift.ID()),
		TechnicianID:      toPGUUID(shift.TechnicianID()),
		DayOfWeek:         int16(shift.DayOfWeek()),
		StartsAt:          toPGTime(shift.StartsAt()),
		EndsAt:            toPGTime(shift.EndsAt()),
		CreatedAt:         shift.CreatedAt(),
		UpdatedAt:         shift.UpdatedAt(),
	})
	return technicianShiftWriteError(err)
}

func (r *DealershipRepository) GetTechnicianShift(ctx context.Context, dealershipID, technicianID, shiftID uuid.UUID) (domain.TechnicianShift, error) {
	row, err := r.queries.GetTechnicianShiftForDealership(ctx, dbmodels.GetTechnicianShiftForDealershipParams{
		TechnicianShiftID: toPGUUID(shiftID),
		TechnicianID:      toPGUUID(technicianID),
		DealershipID:      toPGUUID(dealershipID),
	})
	return technicianShiftFromRow(row.TechnicianShiftID, row.TechnicianID, row.DayOfWeek, row.StartsAt, row.EndsAt, row.CreatedAt, row.UpdatedAt, err)
}

func (r *DealershipRepository) ListTechnicianShifts(ctx context.Context, dealershipID, technicianID uuid.UUID) ([]domain.TechnicianShift, error) {
	rows, err := r.queries.ListTechnicianShiftsForDealership(ctx, dbmodels.ListTechnicianShiftsForDealershipParams{TechnicianID: toPGUUID(technicianID), DealershipID: toPGUUID(dealershipID)})
	if err != nil {
		return nil, err
	}
	shifts := make([]domain.TechnicianShift, 0, len(rows))
	for _, row := range rows {
		shift, err := technicianShiftFromRow(row.TechnicianShiftID, row.TechnicianID, row.DayOfWeek, row.StartsAt, row.EndsAt, row.CreatedAt, row.UpdatedAt, nil)
		if err != nil {
			return nil, err
		}
		shifts = append(shifts, shift)
	}
	return shifts, nil
}

func (r *DealershipRepository) UpdateTechnicianShift(ctx context.Context, dealershipID uuid.UUID, shift domain.TechnicianShift) error {
	rows, err := r.queries.UpdateTechnicianShiftForDealership(ctx, dbmodels.UpdateTechnicianShiftForDealershipParams{
		DayOfWeek:         int16(shift.DayOfWeek()),
		StartsAt:          toPGTime(shift.StartsAt()),
		EndsAt:            toPGTime(shift.EndsAt()),
		UpdatedAt:         shift.UpdatedAt(),
		TechnicianShiftID: toPGUUID(shift.ID()),
		TechnicianID:      toPGUUID(shift.TechnicianID()),
		DealershipID:      toPGUUID(dealershipID),
	})
	if err = technicianShiftWriteError(err); err != nil {
		return err
	}
	if rows == 0 {
		return app.ErrTechnicianShiftNotFound
	}
	return nil
}

func (r *DealershipRepository) DeleteTechnicianShift(ctx context.Context, dealershipID, technicianID, shiftID uuid.UUID, now time.Time) error {
	rows, err := r.queries.DeleteTechnicianShiftForDealership(ctx, dbmodels.DeleteTechnicianShiftForDealershipParams{
		DeletedAt:         pgtype.Timestamptz{Time: now.UTC(), Valid: true},
		TechnicianShiftID: toPGUUID(shiftID),
		TechnicianID:      toPGUUID(technicianID),
		DealershipID:      toPGUUID(dealershipID),
	})
	if err != nil {
		return err
	}
	if rows == 0 {
		return app.ErrTechnicianShiftNotFound
	}
	return nil
}

func (r *DealershipRepository) HasFutureAppointmentsOutsideTechnicianShift(ctx context.Context, technicianID uuid.UUID, candidate domain.TechnicianShift, excludedShiftID uuid.UUID, now time.Time) (bool, error) {
	return r.queries.HasFutureAppointmentsOutsideTechnicianShift(ctx, dbmodels.HasFutureAppointmentsOutsideTechnicianShiftParams{
		TechnicianID:       toPGUUID(technicianID),
		Now:                now.UTC(),
		ExcludedShiftID:    toPGUUID(excludedShiftID),
		CandidateDayOfWeek: int16(candidate.DayOfWeek()),
		CandidateStartsAt:  toPGTime(candidate.StartsAt()),
		CandidateEndsAt:    toPGTime(candidate.EndsAt()),
	})
}

func technicianShiftFromRow(id, technicianID pgtype.UUID, dayOfWeek int16, startsAt, endsAt pgtype.Time, createdAt, updatedAt time.Time, err error) (domain.TechnicianShift, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.TechnicianShift{}, app.ErrTechnicianShiftNotFound
	}
	if err != nil {
		return domain.TechnicianShift{}, err
	}
	return domain.RehydrateTechnicianShift(fromPGUUID(id), fromPGUUID(technicianID), int(dayOfWeek), time.Duration(startsAt.Microseconds)*time.Microsecond, time.Duration(endsAt.Microseconds)*time.Microsecond, createdAt, updatedAt)
}

func technicianShiftWriteError(err error) error {
	var postgresErr *pgconn.PgError
	if errors.As(err, &postgresErr) && postgresErr.Code == "23P01" && postgresErr.ConstraintName == "technician_shifts_no_overlap" {
		return app.ErrTechnicianShiftOverlaps
	}
	return err
}

func (r *DealershipRepository) CreateTechnicianSkill(ctx context.Context, technicianSkill domain.TechnicianSkill) (domain.TechnicianSkill, error) {
	if err := r.ensureActiveTechnicianSkillTargets(ctx, technicianSkill.TechnicianID(), technicianSkill.SkillID()); err != nil {
		return domain.TechnicianSkill{}, err
	}
	row, err := r.queries.CreateTechnicianSkill(ctx, dbmodels.CreateTechnicianSkillParams{
		TechnicianSkillID: toPGUUID(technicianSkill.ID()),
		TechnicianID:      toPGUUID(technicianSkill.TechnicianID()),
		SkillID:           toPGUUID(technicianSkill.SkillID()),
		CreatedAt:         technicianSkill.CreatedAt(),
		UpdatedAt:         technicianSkill.UpdatedAt(),
	})
	return technicianSkillFromRow(row.TechnicianSkillID, row.TechnicianID, row.SkillID, row.CreatedAt, row.UpdatedAt, err)
}

func (r *DealershipRepository) GetTechnicianSkill(ctx context.Context, technicianID, technicianSkillID uuid.UUID) (domain.TechnicianSkill, error) {
	row, err := r.queries.GetTechnicianSkill(ctx, dbmodels.GetTechnicianSkillParams{
		TechnicianID:      toPGUUID(technicianID),
		TechnicianSkillID: toPGUUID(technicianSkillID),
	})
	return technicianSkillFromRow(row.TechnicianSkillID, row.TechnicianID, row.SkillID, row.CreatedAt, row.UpdatedAt, err)
}

func (r *DealershipRepository) ListTechnicianSkills(ctx context.Context, technicianID uuid.UUID) ([]domain.TechnicianSkill, error) {
	if _, err := r.queries.GetActiveTechnician(ctx, toPGUUID(technicianID)); errors.Is(err, pgx.ErrNoRows) {
		return nil, app.ErrTechnicianNotFound
	} else if err != nil {
		return nil, err
	}
	rows, err := r.queries.ListTechnicianSkills(ctx, toPGUUID(technicianID))
	if err != nil {
		return nil, err
	}
	items := make([]domain.TechnicianSkill, 0, len(rows))
	for _, row := range rows {
		item, err := technicianSkillFromRow(row.TechnicianSkillID, row.TechnicianID, row.SkillID, row.CreatedAt, row.UpdatedAt, nil)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, nil
}

func (r *DealershipRepository) UpdateTechnicianSkill(ctx context.Context, technicianSkill domain.TechnicianSkill) (domain.TechnicianSkill, error) {
	if err := r.ensureActiveTechnicianSkillTargets(ctx, technicianSkill.TechnicianID(), technicianSkill.SkillID()); err != nil {
		return domain.TechnicianSkill{}, err
	}
	row, err := r.queries.UpdateTechnicianSkill(ctx, dbmodels.UpdateTechnicianSkillParams{
		TechnicianSkillID: toPGUUID(technicianSkill.ID()),
		TechnicianID:      toPGUUID(technicianSkill.TechnicianID()),
		SkillID:           toPGUUID(technicianSkill.SkillID()),
		UpdatedAt:         technicianSkill.UpdatedAt(),
	})
	return technicianSkillFromRow(row.TechnicianSkillID, row.TechnicianID, row.SkillID, row.CreatedAt, row.UpdatedAt, err)
}

func (r *DealershipRepository) DeleteTechnicianSkill(ctx context.Context, technicianID, technicianSkillID uuid.UUID) error {
	if _, err := r.queries.GetActiveTechnician(ctx, toPGUUID(technicianID)); errors.Is(err, pgx.ErrNoRows) {
		return app.ErrTechnicianNotFound
	} else if err != nil {
		return err
	}
	deleted, err := r.queries.DeleteTechnicianSkill(ctx, dbmodels.DeleteTechnicianSkillParams{
		TechnicianID:      toPGUUID(technicianID),
		TechnicianSkillID: toPGUUID(technicianSkillID),
	})
	if err != nil {
		return err
	}
	if deleted == 0 {
		return app.ErrTechnicianSkillNotFound
	}
	return nil
}

func technicianSkillFromRow(id, technicianID, skillID pgtype.UUID, createdAt, updatedAt time.Time, err error) (domain.TechnicianSkill, error) {
	if common.IsUniqueViolationError(err, "technician_skills_technician_skill_unique") {
		return domain.TechnicianSkill{}, app.ErrTechnicianSkillTaken
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.TechnicianSkill{}, app.ErrTechnicianSkillNotFound
	}
	if err != nil {
		return domain.TechnicianSkill{}, err
	}
	return domain.RehydrateTechnicianSkill(fromPGUUID(id), fromPGUUID(technicianID), fromPGUUID(skillID), createdAt, updatedAt)
}

func (r *DealershipRepository) ensureActiveTechnicianSkillTargets(ctx context.Context, technicianID, skillID uuid.UUID) error {
	if _, err := r.queries.GetActiveTechnician(ctx, toPGUUID(technicianID)); errors.Is(err, pgx.ErrNoRows) {
		return app.ErrTechnicianNotFound
	} else if err != nil {
		return err
	}
	isActive, err := r.queries.ActiveSkillExists(ctx, toPGUUID(skillID))
	if err != nil {
		return err
	}
	if !isActive {
		return app.ErrSkillNotFound
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
