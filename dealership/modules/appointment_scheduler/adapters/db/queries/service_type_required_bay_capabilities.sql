-- Required bay capabilities are selected through their dealership-owned service type.

-- name: BayCapabilityExists :one
SELECT EXISTS(SELECT 1 FROM appointment_scheduler.bay_capabilities WHERE bay_capability_id = sqlc.arg('bay_capability_id'));

-- name: CreateServiceTypeRequiredBayCapability :one
INSERT INTO appointment_scheduler.service_type_required_bay_capabilities (service_type_required_bay_capability_id, service_type_id, bay_capability_id, created_at, updated_at)
SELECT sqlc.arg('service_type_required_bay_capability_id'), service_types.service_type_id, bay_capabilities.bay_capability_id, sqlc.arg('created_at'), sqlc.arg('updated_at')
FROM appointment_scheduler.service_types
JOIN appointment_scheduler.bay_capabilities ON bay_capabilities.bay_capability_id = sqlc.arg('bay_capability_id')
WHERE service_types.service_type_id = sqlc.arg('service_type_id') AND service_types.dealership_id = sqlc.arg('dealership_id') AND service_types.deleted_at IS NULL
RETURNING service_type_required_bay_capability_id, service_type_id, bay_capability_id, created_at, updated_at;

-- name: GetServiceTypeRequiredBayCapability :one
SELECT required_capability.service_type_required_bay_capability_id, required_capability.service_type_id, capabilities.bay_capability_id, capabilities.code, capabilities.name, required_capability.created_at, required_capability.updated_at
FROM appointment_scheduler.service_type_required_bay_capabilities required_capability
JOIN appointment_scheduler.service_types service_types ON service_types.service_type_id = required_capability.service_type_id
JOIN appointment_scheduler.bay_capabilities capabilities ON capabilities.bay_capability_id = required_capability.bay_capability_id
WHERE required_capability.service_type_required_bay_capability_id = sqlc.arg('service_type_required_bay_capability_id') AND required_capability.service_type_id = sqlc.arg('service_type_id') AND service_types.dealership_id = sqlc.arg('dealership_id') AND service_types.deleted_at IS NULL;

-- name: ListServiceTypeRequiredBayCapabilities :many
SELECT required_capability.service_type_required_bay_capability_id, required_capability.service_type_id, capabilities.bay_capability_id, capabilities.code, capabilities.name, required_capability.created_at, required_capability.updated_at
FROM appointment_scheduler.service_type_required_bay_capabilities required_capability
JOIN appointment_scheduler.service_types service_types ON service_types.service_type_id = required_capability.service_type_id
JOIN appointment_scheduler.bay_capabilities capabilities ON capabilities.bay_capability_id = required_capability.bay_capability_id
WHERE required_capability.service_type_id = sqlc.arg('service_type_id') AND service_types.dealership_id = sqlc.arg('dealership_id') AND service_types.deleted_at IS NULL
ORDER BY capabilities.name, capabilities.bay_capability_id;

-- name: UpdateServiceTypeRequiredBayCapability :one
UPDATE appointment_scheduler.service_type_required_bay_capabilities required_capability
SET bay_capability_id = sqlc.arg('bay_capability_id'), updated_at = sqlc.arg('updated_at')
FROM appointment_scheduler.service_types service_types
WHERE required_capability.service_type_required_bay_capability_id = sqlc.arg('service_type_required_bay_capability_id') AND required_capability.service_type_id = sqlc.arg('service_type_id') AND service_types.service_type_id = required_capability.service_type_id AND service_types.dealership_id = sqlc.arg('dealership_id') AND service_types.deleted_at IS NULL
RETURNING required_capability.service_type_required_bay_capability_id, required_capability.service_type_id, required_capability.bay_capability_id, required_capability.created_at, required_capability.updated_at;

-- name: DeleteServiceTypeRequiredBayCapability :execrows
DELETE FROM appointment_scheduler.service_type_required_bay_capabilities required_capability
USING appointment_scheduler.service_types service_types
WHERE required_capability.service_type_required_bay_capability_id = sqlc.arg('service_type_required_bay_capability_id') AND required_capability.service_type_id = sqlc.arg('service_type_id') AND service_types.service_type_id = required_capability.service_type_id AND service_types.dealership_id = sqlc.arg('dealership_id') AND service_types.deleted_at IS NULL;
