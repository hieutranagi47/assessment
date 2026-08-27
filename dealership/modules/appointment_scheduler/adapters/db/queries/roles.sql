-- roles CRUD queries.

-- name: GetRoleByCode :one
SELECT role_id, code
FROM appointment_scheduler.roles
WHERE code = sqlc.arg('code')
  AND deleted_at IS NULL;

-- name: GetRoles :one
SELECT role_id, code, name, description, created_at, updated_at, deleted_at
FROM appointment_scheduler.roles
WHERE role_id = sqlc.arg('role_id') AND deleted_at IS NULL;

-- name: CreateRoles :exec
INSERT INTO appointment_scheduler.roles (role_id, code, name, description, created_at, updated_at)
VALUES (sqlc.arg('role_id'), sqlc.arg('code'), sqlc.arg('name'), sqlc.narg('description'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateRoles :execrows
UPDATE appointment_scheduler.roles
SET code = sqlc.arg('code'), name = sqlc.arg('name'), description = sqlc.narg('description'), updated_at = sqlc.arg('updated_at')
WHERE role_id = sqlc.arg('role_id') AND deleted_at IS NULL;

-- name: DeleteRoles :execrows
UPDATE appointment_scheduler.roles
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE role_id = sqlc.arg('role_id') AND deleted_at IS NULL;
