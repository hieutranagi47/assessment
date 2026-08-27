-- service bays CRUD queries.

-- name: GetServiceBay :one
SELECT service_bay_id, dealership_id, code, name, is_active, created_at, updated_at
FROM appointment_scheduler.service_bays
WHERE service_bay_id = sqlc.arg('service_bay_id')
  AND dealership_id = sqlc.arg('dealership_id')
  AND deleted_at IS NULL;

-- name: ListServiceBays :many
SELECT service_bay_id, dealership_id, code, name, is_active, created_at, updated_at
FROM appointment_scheduler.service_bays
WHERE dealership_id = sqlc.arg('dealership_id')
  AND deleted_at IS NULL
  AND (sqlc.narg('is_active')::boolean IS NULL OR is_active = sqlc.narg('is_active')::boolean)
ORDER BY code, service_bay_id
LIMIT sqlc.arg('limit_count') OFFSET sqlc.arg('offset_count');

-- name: CreateServiceBay :exec
INSERT INTO appointment_scheduler.service_bays (service_bay_id, dealership_id, code, name, is_active, created_at, updated_at)
VALUES (sqlc.arg('service_bay_id'), sqlc.arg('dealership_id'), sqlc.arg('code'), sqlc.arg('name'), sqlc.arg('is_active'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateServiceBay :execrows
UPDATE appointment_scheduler.service_bays
SET code = sqlc.arg('code'), name = sqlc.arg('name'), is_active = sqlc.arg('is_active'), updated_at = sqlc.arg('updated_at')
WHERE service_bay_id = sqlc.arg('service_bay_id')
  AND dealership_id = sqlc.arg('dealership_id')
  AND deleted_at IS NULL;

-- name: DeleteServiceBay :execrows
UPDATE appointment_scheduler.service_bays
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE service_bay_id = sqlc.arg('service_bay_id')
  AND dealership_id = sqlc.arg('dealership_id')
  AND deleted_at IS NULL;

-- name: HasAppointmentsForServiceBay :one
SELECT EXISTS(
  SELECT 1
  FROM appointment_scheduler.appointments
  WHERE service_bay_id = sqlc.arg('service_bay_id')
    AND deleted_at IS NULL
);
