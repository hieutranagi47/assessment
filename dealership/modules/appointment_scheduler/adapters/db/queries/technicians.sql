-- technicians CRUD queries.

-- name: GetTechnicians :one
SELECT technician_id, user_id, is_active, created_at, updated_at, deleted_at
FROM appointment_scheduler.technicians
WHERE technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL;

-- name: CreateTechnicians :exec
INSERT INTO appointment_scheduler.technicians (technician_id, user_id, is_active, created_at, updated_at)
VALUES (sqlc.arg('technician_id'), sqlc.arg('user_id'), sqlc.arg('is_active'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateTechnicians :execrows
UPDATE appointment_scheduler.technicians
SET user_id = sqlc.arg('user_id'), is_active = sqlc.arg('is_active'), updated_at = sqlc.arg('updated_at')
WHERE technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL;

-- name: DeleteTechnicians :execrows
UPDATE appointment_scheduler.technicians
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL;

