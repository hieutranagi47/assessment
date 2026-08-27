-- service type required bay capabilities CRUD queries.

-- name: GetServiceTypeRequiredBayCapabilities :one
SELECT service_type_required_bay_capability_id, service_type_id, capability_code, created_at, deleted_at
FROM appointment_scheduler.service_type_required_bay_capabilities
WHERE service_type_required_bay_capability_id = sqlc.arg('service_type_required_bay_capability_id') AND deleted_at IS NULL;

-- name: CreateServiceTypeRequiredBayCapabilities :exec
INSERT INTO appointment_scheduler.service_type_required_bay_capabilities (service_type_required_bay_capability_id, service_type_id, capability_code, created_at)
VALUES (sqlc.arg('service_type_required_bay_capability_id'), sqlc.arg('service_type_id'), sqlc.arg('capability_code'), sqlc.arg('created_at'));

-- name: UpdateServiceTypeRequiredBayCapabilities :execrows
UPDATE appointment_scheduler.service_type_required_bay_capabilities
SET service_type_id = sqlc.arg('service_type_id'), capability_code = sqlc.arg('capability_code')
WHERE service_type_required_bay_capability_id = sqlc.arg('service_type_required_bay_capability_id') AND deleted_at IS NULL;

-- name: DeleteServiceTypeRequiredBayCapabilities :execrows
UPDATE appointment_scheduler.service_type_required_bay_capabilities
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE service_type_required_bay_capability_id = sqlc.arg('service_type_required_bay_capability_id') AND deleted_at IS NULL;

