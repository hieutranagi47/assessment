-- technician shifts CRUD queries.

-- name: GetTechnicianShifts :one
SELECT technician_shift_id, technician_id, day_of_week, starts_at, ends_at, created_at, updated_at, deleted_at
FROM appointment_scheduler.technician_shifts
WHERE technician_shift_id = sqlc.arg('technician_shift_id') AND deleted_at IS NULL;

-- name: CreateTechnicianShifts :exec
INSERT INTO appointment_scheduler.technician_shifts (technician_shift_id, technician_id, day_of_week, starts_at, ends_at, created_at, updated_at)
VALUES (sqlc.arg('technician_shift_id'), sqlc.arg('technician_id'), sqlc.arg('day_of_week'), sqlc.arg('starts_at'), sqlc.arg('ends_at'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateTechnicianShifts :execrows
UPDATE appointment_scheduler.technician_shifts
SET technician_id = sqlc.arg('technician_id'), day_of_week = sqlc.arg('day_of_week'), starts_at = sqlc.arg('starts_at'), ends_at = sqlc.arg('ends_at'), updated_at = sqlc.arg('updated_at')
WHERE technician_shift_id = sqlc.arg('technician_shift_id') AND deleted_at IS NULL;

-- name: DeleteTechnicianShifts :execrows
UPDATE appointment_scheduler.technician_shifts
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE technician_shift_id = sqlc.arg('technician_shift_id') AND deleted_at IS NULL;

