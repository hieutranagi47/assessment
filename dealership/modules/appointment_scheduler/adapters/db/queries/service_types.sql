-- service types CRUD queries.

-- name: GetServiceType :one
SELECT service_type_id, dealership_id, name, default_duration_minutes, min_duration_minutes, max_duration_minutes, is_active, created_at, updated_at
FROM appointment_scheduler.service_types
WHERE service_type_id = sqlc.arg('service_type_id')
  AND dealership_id = sqlc.arg('dealership_id')
  AND deleted_at IS NULL;

-- name: ListServiceTypes :many
SELECT service_type_id, dealership_id, name, default_duration_minutes, min_duration_minutes, max_duration_minutes, is_active, created_at, updated_at
FROM appointment_scheduler.service_types
WHERE dealership_id = sqlc.arg('dealership_id') AND deleted_at IS NULL
ORDER BY name, service_type_id;

-- name: CreateServiceTypes :exec
INSERT INTO appointment_scheduler.service_types (service_type_id, dealership_id, name, default_duration_minutes, min_duration_minutes, max_duration_minutes, is_active, created_at, updated_at)
VALUES (sqlc.arg('service_type_id'), sqlc.arg('dealership_id'), sqlc.arg('name'), sqlc.arg('default_duration_minutes'), sqlc.arg('min_duration_minutes'), sqlc.arg('max_duration_minutes'), sqlc.arg('is_active'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateServiceTypes :execrows
UPDATE appointment_scheduler.service_types
SET name = sqlc.arg('name'), default_duration_minutes = sqlc.arg('default_duration_minutes'), min_duration_minutes = sqlc.arg('min_duration_minutes'), max_duration_minutes = sqlc.arg('max_duration_minutes'), is_active = sqlc.arg('is_active'), updated_at = sqlc.arg('updated_at')
WHERE service_type_id = sqlc.arg('service_type_id')
  AND dealership_id = sqlc.arg('dealership_id')
  AND deleted_at IS NULL;

-- name: DeleteServiceTypes :execrows
UPDATE appointment_scheduler.service_types
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE service_type_id = sqlc.arg('service_type_id')
  AND dealership_id = sqlc.arg('dealership_id')
  AND deleted_at IS NULL;

-- name: HasAppointmentsForServiceType :one
SELECT EXISTS(
  SELECT 1
  FROM appointment_scheduler.appointments
  WHERE service_type_id = sqlc.arg('service_type_id')
);
