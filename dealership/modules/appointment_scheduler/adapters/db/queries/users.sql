-- users CRUD queries.

-- name: GetSchedulerUserByAuthUserID :one
SELECT user_id
FROM appointment_scheduler.users
WHERE auth_user_id = sqlc.arg('auth_user_id')
  AND deleted_at IS NULL;

-- name: IsActiveSchedulerAdmin :one
SELECT EXISTS (
  SELECT 1
  FROM appointment_scheduler.users AS users
  JOIN appointment_scheduler.user_roles AS user_roles
    ON user_roles.user_id = users.user_id
  JOIN appointment_scheduler.roles AS roles
    ON roles.role_id = user_roles.role_id
  WHERE users.auth_user_id = sqlc.arg('auth_user_id')
    AND users.is_active
    AND users.deleted_at IS NULL
    AND user_roles.deleted_at IS NULL
    AND roles.code = 'admin'
    AND roles.deleted_at IS NULL
);

-- name: IsActiveSchedulerAdminForDealership :one
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
    AND roles.code = 'admin'
    AND roles.deleted_at IS NULL
);

-- name: CreateSchedulerUser :one
WITH created_user AS (
  INSERT INTO appointment_scheduler.users (
    user_id, auth_user_id, name, email, dealership_id, is_active, created_at, updated_at
  ) VALUES (
    sqlc.arg('user_id'), sqlc.arg('auth_user_id'), sqlc.arg('name'), sqlc.arg('email'),
    sqlc.arg('dealership_id'), TRUE, sqlc.arg('created_at'), sqlc.arg('updated_at')
  )
  RETURNING user_id, auth_user_id, name, email, dealership_id, is_active, created_at, updated_at
), created_role AS (
  INSERT INTO appointment_scheduler.user_roles (user_role_id, user_id, role_id, created_at)
  SELECT sqlc.arg('user_role_id'), user_id, sqlc.arg('role_id'), sqlc.arg('created_at')
  FROM created_user
)
SELECT user_id, auth_user_id, name, email, dealership_id, is_active, created_at, updated_at
FROM created_user;

-- name: CreateSchedulerAdmin :one
WITH created_user AS (
  INSERT INTO appointment_scheduler.users (
    user_id,
    auth_user_id,
    name,
    phone,
    email,
    dealership_id,
    is_active,
    created_at,
    updated_at
  )
  VALUES (
    sqlc.arg('user_id'),
    sqlc.arg('auth_user_id'),
    sqlc.arg('name'),
    sqlc.narg('phone'),
    sqlc.narg('email'),
    sqlc.arg('dealership_id'),
    TRUE,
    sqlc.arg('created_at'),
    sqlc.arg('updated_at')
  )
  RETURNING user_id, auth_user_id, name, phone, email, dealership_id, is_active, created_at, updated_at
), created_role AS (
  INSERT INTO appointment_scheduler.user_roles (user_role_id, user_id, role_id, created_at)
  SELECT sqlc.arg('user_role_id'), created_user.user_id, sqlc.arg('role_id'), sqlc.arg('created_at')
  FROM created_user
)
SELECT user_id, auth_user_id, name, phone, email, dealership_id, is_active, created_at, updated_at
FROM created_user;

-- name: GetUsers :one
SELECT user_id, auth_user_id, name, phone, email, dealership_id, is_active, created_at, updated_at, deleted_at
FROM appointment_scheduler.users
WHERE user_id = sqlc.arg('user_id') AND deleted_at IS NULL;

-- name: CreateUsers :exec
INSERT INTO appointment_scheduler.users (user_id, auth_user_id, name, phone, email, dealership_id, is_active, created_at, updated_at)
VALUES (sqlc.arg('user_id'), sqlc.arg('auth_user_id'), sqlc.arg('name'), sqlc.narg('phone'), sqlc.narg('email'), sqlc.arg('dealership_id'), sqlc.arg('is_active'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateUsers :execrows
UPDATE appointment_scheduler.users
SET auth_user_id = sqlc.arg('auth_user_id'), name = sqlc.arg('name'), phone = sqlc.narg('phone'), email = sqlc.narg('email'), dealership_id = sqlc.arg('dealership_id'), is_active = sqlc.arg('is_active'), updated_at = sqlc.arg('updated_at')
WHERE user_id = sqlc.arg('user_id') AND deleted_at IS NULL;

-- name: DeleteUsers :execrows
UPDATE appointment_scheduler.users
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE user_id = sqlc.arg('user_id') AND deleted_at IS NULL;
