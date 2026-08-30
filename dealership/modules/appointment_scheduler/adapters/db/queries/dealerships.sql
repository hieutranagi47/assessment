-- dealerships CRUD queries.

-- name: ListDealerships :many
SELECT dealership_id, name, code, address, timezone, is_active, created_at, updated_at
FROM appointment_scheduler.dealerships
WHERE deleted_at IS NULL
ORDER BY name, dealership_id;

-- name: GetActiveDealership :one
SELECT dealership_id
FROM appointment_scheduler.dealerships
WHERE dealership_id = sqlc.arg('dealership_id')
  AND is_active = TRUE
  AND deleted_at IS NULL;

-- name: GetDealerships :one
SELECT dealership_id, name, code, address, timezone, is_active, created_at, updated_at, deleted_at
FROM appointment_scheduler.dealerships
WHERE dealership_id = sqlc.arg('dealership_id') AND deleted_at IS NULL;

-- name: CreateDealerships :exec
INSERT INTO appointment_scheduler.dealerships (dealership_id, name, code, address, timezone, is_active, created_at, updated_at)
VALUES (sqlc.arg('dealership_id'), sqlc.arg('name'), sqlc.arg('code'), sqlc.arg('address'), sqlc.arg('timezone'), sqlc.arg('is_active'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateDealerships :execrows
UPDATE appointment_scheduler.dealerships
SET name = sqlc.arg('name'), code = sqlc.arg('code'), address = sqlc.arg('address'), timezone = sqlc.arg('timezone'), is_active = sqlc.arg('is_active'), updated_at = sqlc.arg('updated_at')
WHERE dealership_id = sqlc.arg('dealership_id') AND deleted_at IS NULL;

-- name: DeleteDealerships :execrows
UPDATE appointment_scheduler.dealerships
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE dealership_id = sqlc.arg('dealership_id') AND deleted_at IS NULL;
