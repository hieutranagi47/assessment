-- name: CreateCustomer :one
INSERT INTO appointment_scheduler.customers (customer_id, name, phone, email, created_at, updated_at)
VALUES (sqlc.arg('customer_id'), sqlc.arg('name'), sqlc.arg('phone'), sqlc.narg('email'), sqlc.arg('created_at'), sqlc.arg('updated_at'))
RETURNING customer_id, name, phone, email, created_at, updated_at;

-- name: GetCustomerByID :one
SELECT customer_id, name, phone, email, created_at, updated_at
FROM appointment_scheduler.customers
WHERE customer_id = sqlc.arg('customer_id');

-- name: UpdateCustomer :one
UPDATE appointment_scheduler.customers
SET name = sqlc.arg('name'), phone = sqlc.arg('phone'), email = sqlc.narg('email'), updated_at = sqlc.arg('updated_at')
WHERE customer_id = sqlc.arg('customer_id')
RETURNING customer_id, name, phone, email, created_at, updated_at;

-- name: GetCustomerByPhone :one
SELECT customer_id, name, phone, email, created_at, updated_at
FROM appointment_scheduler.customers
WHERE phone = sqlc.arg('phone');

-- name: GetCustomerByEmail :one
SELECT customer_id, name, phone, email, created_at, updated_at
FROM appointment_scheduler.customers
WHERE lower(email) = sqlc.arg('email');
