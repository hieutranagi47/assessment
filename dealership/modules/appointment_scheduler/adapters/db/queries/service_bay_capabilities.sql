-- Service-bay assignments are always selected through their dealership-owned bay.

-- name: CreateServiceBayCapability :one
INSERT INTO appointment_scheduler.service_bay_capabilities (service_bay_capability_id, service_bay_id, bay_capability_id, created_at, updated_at)
SELECT sqlc.arg('service_bay_capability_id'), service_bays.service_bay_id, bay_capabilities.bay_capability_id, sqlc.arg('created_at'), sqlc.arg('updated_at')
FROM appointment_scheduler.service_bays
JOIN appointment_scheduler.bay_capabilities ON bay_capabilities.bay_capability_id = sqlc.arg('bay_capability_id')
WHERE service_bays.service_bay_id = sqlc.arg('service_bay_id') AND service_bays.dealership_id = sqlc.arg('dealership_id') AND service_bays.deleted_at IS NULL
RETURNING service_bay_capability_id, service_bay_id, bay_capability_id, created_at, updated_at;

-- name: GetServiceBayCapability :one
SELECT assigned_capability.service_bay_capability_id, assigned_capability.service_bay_id, capabilities.bay_capability_id, capabilities.code, capabilities.name, assigned_capability.created_at, assigned_capability.updated_at
FROM appointment_scheduler.service_bay_capabilities assigned_capability
JOIN appointment_scheduler.service_bays service_bays ON service_bays.service_bay_id = assigned_capability.service_bay_id
JOIN appointment_scheduler.bay_capabilities capabilities ON capabilities.bay_capability_id = assigned_capability.bay_capability_id
WHERE assigned_capability.service_bay_capability_id = sqlc.arg('service_bay_capability_id') AND assigned_capability.service_bay_id = sqlc.arg('service_bay_id') AND service_bays.dealership_id = sqlc.arg('dealership_id') AND service_bays.deleted_at IS NULL;

-- name: ListServiceBayCapabilities :many
SELECT assigned_capability.service_bay_capability_id, assigned_capability.service_bay_id, capabilities.bay_capability_id, capabilities.code, capabilities.name, assigned_capability.created_at, assigned_capability.updated_at
FROM appointment_scheduler.service_bay_capabilities assigned_capability
JOIN appointment_scheduler.service_bays service_bays ON service_bays.service_bay_id = assigned_capability.service_bay_id
JOIN appointment_scheduler.bay_capabilities capabilities ON capabilities.bay_capability_id = assigned_capability.bay_capability_id
WHERE assigned_capability.service_bay_id = sqlc.arg('service_bay_id') AND service_bays.dealership_id = sqlc.arg('dealership_id') AND service_bays.deleted_at IS NULL
ORDER BY capabilities.name, capabilities.bay_capability_id;

-- name: UpdateServiceBayCapability :one
UPDATE appointment_scheduler.service_bay_capabilities assigned_capability
SET bay_capability_id = sqlc.arg('bay_capability_id'), updated_at = sqlc.arg('updated_at')
FROM appointment_scheduler.service_bays service_bays
WHERE assigned_capability.service_bay_capability_id = sqlc.arg('service_bay_capability_id') AND assigned_capability.service_bay_id = sqlc.arg('service_bay_id') AND service_bays.service_bay_id = assigned_capability.service_bay_id AND service_bays.dealership_id = sqlc.arg('dealership_id') AND service_bays.deleted_at IS NULL
RETURNING assigned_capability.service_bay_capability_id, assigned_capability.service_bay_id, assigned_capability.bay_capability_id, assigned_capability.created_at, assigned_capability.updated_at;

-- name: DeleteServiceBayCapability :execrows
DELETE FROM appointment_scheduler.service_bay_capabilities assigned_capability
USING appointment_scheduler.service_bays service_bays
WHERE assigned_capability.service_bay_capability_id = sqlc.arg('service_bay_capability_id') AND assigned_capability.service_bay_id = sqlc.arg('service_bay_id') AND service_bays.service_bay_id = assigned_capability.service_bay_id AND service_bays.dealership_id = sqlc.arg('dealership_id') AND service_bays.deleted_at IS NULL;
