-- name: CreateAppointmentResourceReservation :exec
INSERT INTO appointment_scheduler.appointment_resource_reservations (
  appointment_resource_reservation_id, appointment_id, resource_type, resource_id,
  reserved_starts_at, reserved_ends_at, status, assigned_at, assigned_by_user_id, reason
) VALUES (
  sqlc.arg('appointment_resource_reservation_id'), sqlc.arg('appointment_id'),
  sqlc.arg('resource_type'), sqlc.arg('resource_id'), sqlc.arg('reserved_starts_at'),
  sqlc.arg('reserved_ends_at'), sqlc.arg('status'), sqlc.arg('assigned_at'),
  sqlc.arg('assigned_by_user_id'), sqlc.narg('reason')
);

-- name: ReleaseAppointmentResourceReservations :execrows
UPDATE appointment_scheduler.appointment_resource_reservations
SET released_at = sqlc.arg('released_at'), status = sqlc.arg('status')
WHERE appointment_id = sqlc.arg('appointment_id')
  AND released_at IS NULL;

-- name: ListAppointmentResourceReservations :many
SELECT appointment_resource_reservation_id, appointment_id, resource_type, resource_id,
  reserved_starts_at, reserved_ends_at, status, assigned_at, released_at,
  assigned_by_user_id, reason
FROM appointment_scheduler.appointment_resource_reservations
WHERE appointment_id = sqlc.arg('appointment_id')
ORDER BY assigned_at, appointment_resource_reservation_id;
