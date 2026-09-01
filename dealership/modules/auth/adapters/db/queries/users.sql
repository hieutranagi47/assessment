-- name: CreateUser :exec
INSERT INTO auth.users (
  user_id, email, email_password, email_password_salt, email_lookup, full_name, hashed_password, hashed_password_1,
  hashed_password_2, token_ver, status, created_at, updated_at
) VALUES (
  sqlc.arg('user_id'),
  sqlc.arg('email'),
  sqlc.arg('email_password'),
  sqlc.arg('email_password_salt'),
  sqlc.arg('email_lookup'),
  sqlc.arg('full_name'),
  sqlc.arg('hashed_password'),
  sqlc.arg('hashed_password_1'),
  sqlc.arg('hashed_password_2'),
  sqlc.arg('token_ver'),
  sqlc.arg('status'),
  sqlc.arg('created_at'),
  sqlc.arg('updated_at')
);

-- name: CreateUserRole :exec
INSERT INTO auth.user_roles (
  user_id, role_id, created_at, updated_at
) SELECT
  sqlc.arg('user_id'),
  roles.role_id,
  sqlc.arg('created_at'),
  sqlc.arg('updated_at')
FROM auth.roles
WHERE roles.name = sqlc.arg('role_name')
ON CONFLICT (user_id) DO UPDATE
SET role_id = EXCLUDED.role_id,
    updated_at = EXCLUDED.updated_at;

-- name: LockInitialAccountCreation :exec
SELECT pg_advisory_xact_lock(48201945);

-- name: HasAnyUser :one
SELECT EXISTS (
  SELECT 1
  FROM auth.users
);

-- name: GetUserByEmail :one
SELECT user_id, email, full_name, hashed_password, hashed_password_1,
       hashed_password_2, token_ver, status, created_at, updated_at
FROM auth.users
WHERE email_lookup = sqlc.arg('email_lookup');

-- name: GetSignInUserByEmail :one
SELECT users.user_id, users.email, users.full_name, users.hashed_password,
       users.hashed_password_1, users.hashed_password_2, users.token_ver,
       users.status, users.created_at, users.updated_at, roles.name AS role
FROM auth.users
JOIN auth.user_roles ON auth.user_roles.user_id = users.user_id
JOIN auth.roles ON roles.role_id = auth.user_roles.role_id
WHERE users.email_lookup = sqlc.arg('email_lookup');

-- name: GetRefreshUserByID :one
SELECT users.user_id, users.email, users.full_name, users.hashed_password,
       users.hashed_password_1, users.hashed_password_2, users.token_ver,
       users.status, users.created_at, users.updated_at, roles.name AS role
FROM auth.users
JOIN auth.user_roles ON auth.user_roles.user_id = users.user_id
JOIN auth.roles ON roles.role_id = auth.user_roles.role_id
WHERE users.user_id = sqlc.arg('user_id');

-- name: GetUserByID :one
SELECT user_id, email, full_name, hashed_password, hashed_password_1,
       hashed_password_2, token_ver, status, created_at, updated_at
FROM auth.users
WHERE user_id = sqlc.arg('user_id');

-- name: GetUserRole :one
SELECT roles.name
FROM auth.user_roles
JOIN auth.roles ON roles.role_id = auth.user_roles.role_id
WHERE auth.user_roles.user_id = sqlc.arg('user_id');

-- name: UpdateUser :execrows
UPDATE auth.users
SET full_name = sqlc.arg('full_name'),
    hashed_password = sqlc.arg('hashed_password'),
    hashed_password_1 = sqlc.arg('hashed_password_1'),
    hashed_password_2 = sqlc.arg('hashed_password_2'),
    token_ver = sqlc.arg('token_ver'),
    status = sqlc.arg('status'),
    updated_at = sqlc.arg('updated_at')
WHERE user_id = sqlc.arg('user_id');

-- name: UpdateUserPasswordAndEmail :execrows
UPDATE auth.users
SET email_password = sqlc.arg('email_password'),
    email_password_salt = sqlc.arg('email_password_salt'),
    hashed_password = sqlc.arg('hashed_password'),
    hashed_password_1 = sqlc.arg('hashed_password_1'),
    hashed_password_2 = sqlc.arg('hashed_password_2'),
    token_ver = sqlc.arg('token_ver'),
    updated_at = sqlc.arg('updated_at')
WHERE user_id = sqlc.arg('user_id');

-- name: GetPasswordEncryptedEmail :one
SELECT email_password, email_password_salt
FROM auth.users
WHERE user_id = sqlc.arg('user_id');

-- name: StoreDeliveryEmail :execrows
UPDATE auth.users
SET email_to = sqlc.arg('email_to')
WHERE user_id = sqlc.arg('user_id');
