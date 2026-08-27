-- customers CRUD queries.

-- name: GetCustomers :one
SELECT customer_id, name, phone, email, created_at, updated_at, deleted_at
FROM appointment_scheduler.customers
WHERE customer_id = sqlc.arg('customer_id') AND deleted_at IS NULL;

-- name: CreateCustomers :exec
INSERT INTO appointment_scheduler.customers (customer_id, name, phone, email, created_at, updated_at)
VALUES (sqlc.arg('customer_id'), sqlc.arg('name'), sqlc.narg('phone'), sqlc.narg('email'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateCustomers :execrows
UPDATE appointment_scheduler.customers
SET name = sqlc.arg('name'), phone = sqlc.narg('phone'), email = sqlc.narg('email'), updated_at = sqlc.arg('updated_at')
WHERE customer_id = sqlc.arg('customer_id') AND deleted_at IS NULL;

-- name: DeleteCustomers :execrows
UPDATE appointment_scheduler.customers
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE customer_id = sqlc.arg('customer_id') AND deleted_at IS NULL;

