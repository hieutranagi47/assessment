-- service bays CRUD queries.

-- name: CanReadAvailableServiceBays :one
SELECT EXISTS (
  SELECT 1
  FROM appointment_scheduler.users AS users
  JOIN appointment_scheduler.user_roles AS user_roles ON user_roles.user_id = users.user_id
  JOIN appointment_scheduler.roles AS roles ON roles.role_id = user_roles.role_id
  WHERE users.auth_user_id = sqlc.arg('auth_user_id')
    AND users.dealership_id = sqlc.arg('dealership_id')
    AND users.is_active
    AND users.deleted_at IS NULL
    AND user_roles.deleted_at IS NULL
    AND roles.deleted_at IS NULL
    AND roles.code IN ('admin', 'staff', 'dealer')
);

-- name: ListAvailableServiceBays :many
SELECT service_bay_id, dealership_id, code, name, is_active, created_at, updated_at
FROM appointment_scheduler.service_bays AS service_bays
WHERE service_bays.dealership_id = sqlc.arg('dealership_id')
  AND is_active
  AND deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM appointment_scheduler.appointments AS appointments
    WHERE appointments.service_bay_id = service_bays.service_bay_id
      AND appointments.deleted_at IS NULL
      AND appointments.status IN ('requested', 'checked_in', 'in_progress')
      AND appointments.starts_at < sqlc.arg('ends_at')
      AND appointments.ends_at > sqlc.arg('starts_at')
  )
  AND NOT EXISTS (
    SELECT 1
    FROM appointment_scheduler.service_type_required_bay_capabilities AS required_capabilities
    WHERE required_capabilities.service_type_id = sqlc.arg('service_type_id')
      AND NOT EXISTS (
        SELECT 1
        FROM appointment_scheduler.service_bay_capabilities AS bay_capabilities
        WHERE bay_capabilities.service_bay_id = service_bays.service_bay_id
          AND bay_capabilities.bay_capability_id = required_capabilities.bay_capability_id
      )
  )
ORDER BY code, service_bay_id;

-- name: IsActiveServiceTypeForAvailableServiceBays :one
SELECT EXISTS (
  SELECT 1
  FROM appointment_scheduler.service_types
  WHERE service_type_id = sqlc.arg('service_type_id')
    AND dealership_id = sqlc.arg('dealership_id')
    AND is_active
    AND deleted_at IS NULL
);

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
