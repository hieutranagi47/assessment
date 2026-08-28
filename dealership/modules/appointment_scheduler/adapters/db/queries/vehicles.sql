-- name: GetVehicle :one
SELECT vehicle_id, customer_id, vin, registration_plate, make, model, model_year, created_at, updated_at, deleted_at
FROM appointment_scheduler.vehicles
WHERE vehicle_id = sqlc.arg('vehicle_id') AND deleted_at IS NULL;

-- name: ListCustomerVehicles :many
SELECT vehicle_id, customer_id, vin, registration_plate, make, model, model_year, created_at, updated_at
FROM appointment_scheduler.vehicles
WHERE customer_id = sqlc.arg('customer_id') AND deleted_at IS NULL
ORDER BY created_at, vehicle_id;

-- name: CreateVehicle :exec
INSERT INTO appointment_scheduler.vehicles (vehicle_id, customer_id, vin, registration_plate, make, model, model_year, created_at, updated_at)
VALUES (sqlc.arg('vehicle_id'), sqlc.arg('customer_id'), sqlc.narg('vin'), sqlc.narg('registration_plate'), sqlc.arg('make'), sqlc.arg('model'), sqlc.narg('model_year'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateVehicle :execrows
UPDATE appointment_scheduler.vehicles
SET vin = sqlc.narg('vin'), registration_plate = sqlc.narg('registration_plate'), make = sqlc.arg('make'), model = sqlc.arg('model'), model_year = sqlc.narg('model_year'), updated_at = sqlc.arg('updated_at')
WHERE vehicle_id = sqlc.arg('vehicle_id') AND deleted_at IS NULL;

-- name: DeleteVehicle :execrows
UPDATE appointment_scheduler.vehicles
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE vehicle_id = sqlc.arg('vehicle_id') AND deleted_at IS NULL;

-- name: GetActiveVehicleManagerDealership :one
SELECT users.dealership_id
FROM appointment_scheduler.users AS users
JOIN appointment_scheduler.user_roles AS user_roles ON user_roles.user_id = users.user_id
JOIN appointment_scheduler.roles AS roles ON roles.role_id = user_roles.role_id
WHERE users.auth_user_id = sqlc.arg('auth_user_id')
  AND users.is_active
  AND users.deleted_at IS NULL
  AND user_roles.deleted_at IS NULL
  AND roles.deleted_at IS NULL
  AND roles.code IN ('admin', 'dealer', 'staff');

-- name: GetCustomerDealership :one
SELECT dealership_id
FROM appointment_scheduler.customer_dealerships
WHERE customer_id = sqlc.arg('customer_id');

-- name: ClaimCustomerDealership :exec
INSERT INTO appointment_scheduler.customer_dealerships (customer_id, dealership_id)
VALUES (sqlc.arg('customer_id'), sqlc.arg('dealership_id'))
ON CONFLICT (customer_id) DO NOTHING;
