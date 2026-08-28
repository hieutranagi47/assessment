-- technician time off CRUD queries.

-- name: GetTechnicianTimeOff :one
SELECT technician_time_off_id, technician_id, starts_at, ends_at, reason, created_by_user_id, created_at, updated_at
FROM appointment_scheduler.technician_time_off
WHERE technician_time_off_id = sqlc.arg('technician_time_off_id') AND technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL;

-- name: ListTechnicianTimeOff :many
SELECT technician_time_off_id, technician_id, starts_at, ends_at, reason, created_by_user_id, created_at, updated_at
FROM appointment_scheduler.technician_time_off
WHERE technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL
  AND (sqlc.narg('from_at')::timestamptz IS NULL OR ends_at > sqlc.narg('from_at')::timestamptz)
  AND (sqlc.narg('to_at')::timestamptz IS NULL OR starts_at < sqlc.narg('to_at')::timestamptz)
ORDER BY starts_at, technician_time_off_id
LIMIT sqlc.arg('limit') OFFSET sqlc.arg('offset');

-- name: CreateTechnicianTimeOff :exec
INSERT INTO appointment_scheduler.technician_time_off (technician_time_off_id, technician_id, starts_at, ends_at, reason, created_by_user_id, created_at, updated_at)
VALUES (sqlc.arg('technician_time_off_id'), sqlc.arg('technician_id'), sqlc.arg('starts_at'), sqlc.arg('ends_at'), sqlc.narg('reason'), sqlc.arg('created_by_user_id'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateTechnicianTimeOff :execrows
UPDATE appointment_scheduler.technician_time_off
SET starts_at = sqlc.arg('starts_at'), ends_at = sqlc.arg('ends_at'), reason = sqlc.narg('reason'), updated_at = sqlc.arg('updated_at')
WHERE technician_time_off_id = sqlc.arg('technician_time_off_id') AND technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL;

-- name: DeleteTechnicianTimeOff :execrows
UPDATE appointment_scheduler.technician_time_off
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE technician_time_off_id = sqlc.arg('technician_time_off_id') AND technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL;
