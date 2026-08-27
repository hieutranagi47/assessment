-- appointment idempotency CRUD queries.

-- name: GetAppointmentIdempotency :one
SELECT idempotency_key, appointment_id, created_at, deleted_at
FROM appointment_scheduler.appointment_idempotency
WHERE idempotency_key = sqlc.arg('idempotency_key') AND deleted_at IS NULL;

-- name: CreateAppointmentIdempotency :exec
INSERT INTO appointment_scheduler.appointment_idempotency (idempotency_key, appointment_id, created_at)
VALUES (sqlc.arg('idempotency_key'), sqlc.narg('appointment_id'), sqlc.arg('created_at'));

-- name: UpdateAppointmentIdempotency :execrows
UPDATE appointment_scheduler.appointment_idempotency
SET appointment_id = sqlc.narg('appointment_id')
WHERE idempotency_key = sqlc.arg('idempotency_key') AND deleted_at IS NULL;

-- name: DeleteAppointmentIdempotency :execrows
UPDATE appointment_scheduler.appointment_idempotency
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE idempotency_key = sqlc.arg('idempotency_key') AND deleted_at IS NULL;

