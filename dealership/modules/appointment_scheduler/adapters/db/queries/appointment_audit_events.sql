-- appointment audit events CRUD queries.

-- name: GetAppointmentAuditEvents :one
SELECT appointment_audit_event_id, appointment_id, actor_user_id, event_type, before_data, after_data, occurred_at, deleted_at
FROM appointment_scheduler.appointment_audit_events
WHERE appointment_audit_event_id = sqlc.arg('appointment_audit_event_id') AND deleted_at IS NULL;

-- name: CreateAppointmentAuditEvents :exec
INSERT INTO appointment_scheduler.appointment_audit_events (appointment_audit_event_id, appointment_id, actor_user_id, event_type, before_data, after_data, occurred_at)
VALUES (sqlc.arg('appointment_audit_event_id'), sqlc.narg('appointment_id'), sqlc.narg('actor_user_id'), sqlc.arg('event_type'), sqlc.narg('before_data'), sqlc.narg('after_data'), sqlc.arg('occurred_at'));

-- name: UpdateAppointmentAuditEvents :execrows
UPDATE appointment_scheduler.appointment_audit_events
SET appointment_id = sqlc.narg('appointment_id'), actor_user_id = sqlc.narg('actor_user_id'), event_type = sqlc.arg('event_type'), before_data = sqlc.narg('before_data'), after_data = sqlc.narg('after_data'), occurred_at = sqlc.arg('occurred_at')
WHERE appointment_audit_event_id = sqlc.arg('appointment_audit_event_id') AND deleted_at IS NULL;

-- name: DeleteAppointmentAuditEvents :execrows
UPDATE appointment_scheduler.appointment_audit_events
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE appointment_audit_event_id = sqlc.arg('appointment_audit_event_id') AND deleted_at IS NULL;

