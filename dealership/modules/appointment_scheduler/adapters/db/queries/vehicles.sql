-- vehicles CRUD queries.

-- name: GetVehicles :one
SELECT vehicle_id, customer_id, vin, registration_plate, make, model, model_year, created_at, updated_at, deleted_at
FROM appointment_scheduler.vehicles
WHERE vehicle_id = sqlc.arg('vehicle_id') AND deleted_at IS NULL;

-- name: CreateVehicles :exec
INSERT INTO appointment_scheduler.vehicles (vehicle_id, customer_id, vin, registration_plate, make, model, model_year, created_at, updated_at)
VALUES (sqlc.arg('vehicle_id'), sqlc.arg('customer_id'), sqlc.narg('vin'), sqlc.narg('registration_plate'), sqlc.arg('make'), sqlc.arg('model'), sqlc.narg('model_year'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateVehicles :execrows
UPDATE appointment_scheduler.vehicles
SET customer_id = sqlc.arg('customer_id'), vin = sqlc.narg('vin'), registration_plate = sqlc.narg('registration_plate'), make = sqlc.arg('make'), model = sqlc.arg('model'), model_year = sqlc.narg('model_year'), updated_at = sqlc.arg('updated_at')
WHERE vehicle_id = sqlc.arg('vehicle_id') AND deleted_at IS NULL;

-- name: DeleteVehicles :execrows
UPDATE appointment_scheduler.vehicles
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE vehicle_id = sqlc.arg('vehicle_id') AND deleted_at IS NULL;
