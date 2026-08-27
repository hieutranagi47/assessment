-- service bay capabilities CRUD queries.

-- name: GetServiceBayCapabilities :one
SELECT service_bay_capability_id, service_bay_id, capability_code, created_at, deleted_at
FROM appointment_scheduler.service_bay_capabilities
WHERE service_bay_capability_id = sqlc.arg('service_bay_capability_id') AND deleted_at IS NULL;

-- name: CreateServiceBayCapabilities :exec
INSERT INTO appointment_scheduler.service_bay_capabilities (service_bay_capability_id, service_bay_id, capability_code, created_at)
VALUES (sqlc.arg('service_bay_capability_id'), sqlc.arg('service_bay_id'), sqlc.arg('capability_code'), sqlc.arg('created_at'));

-- name: UpdateServiceBayCapabilities :execrows
UPDATE appointment_scheduler.service_bay_capabilities
SET service_bay_id = sqlc.arg('service_bay_id'), capability_code = sqlc.arg('capability_code')
WHERE service_bay_capability_id = sqlc.arg('service_bay_capability_id') AND deleted_at IS NULL;

-- name: DeleteServiceBayCapabilities :execrows
UPDATE appointment_scheduler.service_bay_capabilities
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE service_bay_capability_id = sqlc.arg('service_bay_capability_id') AND deleted_at IS NULL;

