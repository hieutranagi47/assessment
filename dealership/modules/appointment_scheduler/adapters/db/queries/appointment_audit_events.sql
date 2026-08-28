-- Appointment audit events are append-only. Only creation and read projection
-- queries belong here; updates and deletes are intentionally not generated.

-- name: CreateAppointmentAuditEvents :exec
INSERT INTO appointment_scheduler.appointment_audit_events (appointment_audit_event_id, appointment_id, actor_user_id, event_type, before_data, after_data, occurred_at)
VALUES (sqlc.arg('appointment_audit_event_id'), sqlc.narg('appointment_id'), sqlc.narg('actor_user_id'), sqlc.arg('event_type'), sqlc.narg('before_data'), sqlc.narg('after_data'), sqlc.arg('occurred_at'));
