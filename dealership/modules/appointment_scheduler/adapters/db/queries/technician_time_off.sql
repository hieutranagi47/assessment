-- technician time off CRUD queries.

-- name: GetTechnicianTimeOff :one
SELECT technician_time_off_id, technician_id, starts_at, ends_at, reason, created_at, deleted_at
FROM appointment_scheduler.technician_time_off
WHERE technician_time_off_id = sqlc.arg('technician_time_off_id') AND deleted_at IS NULL;

-- name: CreateTechnicianTimeOff :exec
INSERT INTO appointment_scheduler.technician_time_off (technician_time_off_id, technician_id, starts_at, ends_at, reason, created_at)
VALUES (sqlc.arg('technician_time_off_id'), sqlc.arg('technician_id'), sqlc.arg('starts_at'), sqlc.arg('ends_at'), sqlc.narg('reason'), sqlc.arg('created_at'));

-- name: UpdateTechnicianTimeOff :execrows
UPDATE appointment_scheduler.technician_time_off
SET technician_id = sqlc.arg('technician_id'), starts_at = sqlc.arg('starts_at'), ends_at = sqlc.arg('ends_at'), reason = sqlc.narg('reason')
WHERE technician_time_off_id = sqlc.arg('technician_time_off_id') AND deleted_at IS NULL;

-- name: DeleteTechnicianTimeOff :execrows
UPDATE appointment_scheduler.technician_time_off
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE technician_time_off_id = sqlc.arg('technician_time_off_id') AND deleted_at IS NULL;

