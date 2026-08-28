-- Technician shift persistence is scoped through the technician's dealership.

-- name: GetTechnicianShiftForDealership :one
SELECT shifts.technician_shift_id, shifts.technician_id, shifts.day_of_week, shifts.starts_at, shifts.ends_at, shifts.created_at, shifts.updated_at
FROM appointment_scheduler.technician_shifts AS shifts
JOIN appointment_scheduler.technicians AS technicians ON technicians.technician_id = shifts.technician_id
JOIN appointment_scheduler.users AS users ON users.user_id = technicians.user_id
WHERE shifts.technician_shift_id = sqlc.arg('technician_shift_id') AND shifts.technician_id = sqlc.arg('technician_id')
  AND users.dealership_id = sqlc.arg('dealership_id')
  AND shifts.deleted_at IS NULL AND technicians.deleted_at IS NULL AND users.deleted_at IS NULL;

-- name: ListTechnicianShiftsForDealership :many
SELECT shifts.technician_shift_id, shifts.technician_id, shifts.day_of_week, shifts.starts_at, shifts.ends_at, shifts.created_at, shifts.updated_at
FROM appointment_scheduler.technician_shifts AS shifts
JOIN appointment_scheduler.technicians AS technicians ON technicians.technician_id = shifts.technician_id
JOIN appointment_scheduler.users AS users ON users.user_id = technicians.user_id
WHERE shifts.technician_id = sqlc.arg('technician_id') AND users.dealership_id = sqlc.arg('dealership_id')
  AND shifts.deleted_at IS NULL AND technicians.deleted_at IS NULL AND users.deleted_at IS NULL
ORDER BY shifts.day_of_week, shifts.starts_at;

-- name: CreateTechnicianShift :exec
INSERT INTO appointment_scheduler.technician_shifts (technician_shift_id, technician_id, day_of_week, starts_at, ends_at, created_at, updated_at)
VALUES (sqlc.arg('technician_shift_id'), sqlc.arg('technician_id'), sqlc.arg('day_of_week'), sqlc.arg('starts_at'), sqlc.arg('ends_at'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateTechnicianShiftForDealership :execrows
UPDATE appointment_scheduler.technician_shifts AS shifts
SET day_of_week = sqlc.arg('day_of_week'), starts_at = sqlc.arg('starts_at'), ends_at = sqlc.arg('ends_at'), updated_at = sqlc.arg('updated_at')
WHERE shifts.technician_shift_id = sqlc.arg('technician_shift_id') AND shifts.technician_id = sqlc.arg('technician_id') AND shifts.deleted_at IS NULL
  AND EXISTS (SELECT 1 FROM appointment_scheduler.technicians AS technicians JOIN appointment_scheduler.users AS users ON users.user_id = technicians.user_id WHERE technicians.technician_id = shifts.technician_id AND users.dealership_id = sqlc.arg('dealership_id') AND technicians.deleted_at IS NULL AND users.deleted_at IS NULL);

-- name: DeleteTechnicianShiftForDealership :execrows
UPDATE appointment_scheduler.technician_shifts AS shifts
SET deleted_at = sqlc.arg('deleted_at'), updated_at = sqlc.arg('deleted_at')
WHERE shifts.technician_shift_id = sqlc.arg('technician_shift_id') AND shifts.technician_id = sqlc.arg('technician_id') AND shifts.deleted_at IS NULL
  AND EXISTS (SELECT 1 FROM appointment_scheduler.technicians AS technicians JOIN appointment_scheduler.users AS users ON users.user_id = technicians.user_id WHERE technicians.technician_id = shifts.technician_id AND users.dealership_id = sqlc.arg('dealership_id') AND technicians.deleted_at IS NULL AND users.deleted_at IS NULL);

-- name: HasFutureAppointmentsOutsideTechnicianShift :one
SELECT EXISTS (
  SELECT 1 FROM appointment_scheduler.appointments AS appointments
  JOIN appointment_scheduler.technicians AS technicians ON technicians.technician_id = appointments.technician_id
  JOIN appointment_scheduler.users AS users ON users.user_id = technicians.user_id
  WHERE appointments.technician_id = sqlc.arg('technician_id') AND appointments.deleted_at IS NULL
    AND appointments.status IN ('requested', 'checked_in', 'in_progress') AND appointments.ends_at > sqlc.arg('now')
    AND NOT EXISTS (
      SELECT 1 FROM appointment_scheduler.technician_shifts AS shifts
      WHERE shifts.technician_id = appointments.technician_id AND shifts.deleted_at IS NULL AND shifts.technician_shift_id <> sqlc.arg('excluded_shift_id')
        AND shifts.day_of_week = EXTRACT(ISODOW FROM appointments.starts_at AT TIME ZONE users.timezone)
        AND (appointments.starts_at AT TIME ZONE users.timezone)::time >= shifts.starts_at
        AND (appointments.ends_at AT TIME ZONE users.timezone)::time <= shifts.ends_at
        AND (appointments.starts_at AT TIME ZONE users.timezone)::date = (appointments.ends_at AT TIME ZONE users.timezone)::date
      UNION ALL SELECT 1
      WHERE sqlc.arg('candidate_day_of_week')::smallint = EXTRACT(ISODOW FROM appointments.starts_at AT TIME ZONE users.timezone)
        AND (appointments.starts_at AT TIME ZONE users.timezone)::time >= sqlc.arg('candidate_starts_at')::time
        AND (appointments.ends_at AT TIME ZONE users.timezone)::time <= sqlc.arg('candidate_ends_at')::time
        AND (appointments.starts_at AT TIME ZONE users.timezone)::date = (appointments.ends_at AT TIME ZONE users.timezone)::date
    )
);
