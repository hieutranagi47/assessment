-- user roles CRUD queries.

-- name: GetUserRoles :one
SELECT user_role_id, user_id, role_id, created_at, deleted_at
FROM appointment_scheduler.user_roles
WHERE user_role_id = sqlc.arg('user_role_id') AND deleted_at IS NULL;

-- name: CreateUserRoles :exec
INSERT INTO appointment_scheduler.user_roles (user_role_id, user_id, role_id, created_at)
VALUES (sqlc.arg('user_role_id'), sqlc.arg('user_id'), sqlc.arg('role_id'), sqlc.arg('created_at'));

-- name: UpdateUserRoles :execrows
UPDATE appointment_scheduler.user_roles
SET user_id = sqlc.arg('user_id'), role_id = sqlc.arg('role_id')
WHERE user_role_id = sqlc.arg('user_role_id') AND deleted_at IS NULL;

-- name: DeleteUserRoles :execrows
UPDATE appointment_scheduler.user_roles
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE user_role_id = sqlc.arg('user_role_id') AND deleted_at IS NULL;

