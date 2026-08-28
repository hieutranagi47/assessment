-- technicians CRUD queries.

-- name: GetGlobalAdminDealership :one
SELECT users.dealership_id
FROM appointment_scheduler.users
JOIN appointment_scheduler.user_roles ON user_roles.user_id = users.user_id
JOIN appointment_scheduler.roles ON roles.role_id = user_roles.role_id
WHERE users.auth_user_id = sqlc.arg('auth_user_id')
  AND users.is_active AND users.deleted_at IS NULL
  AND user_roles.deleted_at IS NULL
  AND roles.code = 'admin' AND roles.deleted_at IS NULL;

-- name: GetActiveSchedulerEmployeeDealership :one
SELECT users.dealership_id
FROM appointment_scheduler.users
WHERE users.auth_user_id = sqlc.arg('auth_user_id')
  AND users.is_active AND users.deleted_at IS NULL;

-- name: GetActiveSchedulerEmployeeID :one
SELECT users.user_id
FROM appointment_scheduler.users
WHERE users.auth_user_id = sqlc.arg('auth_user_id')
  AND users.is_active AND users.deleted_at IS NULL;

-- name: CreateTechnician :one
WITH created_user AS (
  INSERT INTO appointment_scheduler.users (
    user_id, auth_user_id, name, phone, email, dealership_id, is_active, created_at, updated_at
  ) VALUES (
    sqlc.arg('user_id'), '00000000-0000-0000-0000-000000000000', sqlc.arg('name'),
    sqlc.arg('phone'), sqlc.narg('email'), sqlc.arg('dealership_id'), sqlc.arg('is_active'),
    sqlc.arg('created_at'), sqlc.arg('updated_at')
  ) RETURNING user_id, name, phone, email, is_active, created_at, updated_at
), created_technician AS (
  INSERT INTO appointment_scheduler.technicians (technician_id, user_id, is_active, created_at, updated_at)
  SELECT sqlc.arg('technician_id'), user_id, is_active, created_at, updated_at FROM created_user
  RETURNING technician_id, user_id, is_active, created_at, updated_at
)
SELECT created_technician.technician_id, created_technician.user_id, created_user.name,
  created_user.phone, created_user.email, created_technician.is_active,
  created_technician.created_at, created_technician.updated_at
FROM created_technician JOIN created_user USING (user_id);

-- name: GetTechnicianForDealership :one
SELECT technicians.technician_id, technicians.user_id, users.name, users.phone, users.email,
  technicians.is_active, technicians.created_at, technicians.updated_at
FROM appointment_scheduler.technicians
JOIN appointment_scheduler.users ON users.user_id = technicians.user_id
WHERE technicians.technician_id = sqlc.arg('technician_id')
  AND users.dealership_id = sqlc.arg('dealership_id')
  AND technicians.deleted_at IS NULL AND users.deleted_at IS NULL;

-- name: ListTechniciansForDealership :many
SELECT technicians.technician_id, technicians.user_id, users.name, users.phone, users.email,
  technicians.is_active, technicians.created_at, technicians.updated_at
FROM appointment_scheduler.technicians
JOIN appointment_scheduler.users ON users.user_id = technicians.user_id
WHERE users.dealership_id = sqlc.arg('dealership_id')
  AND (sqlc.narg('is_active')::boolean IS NULL OR technicians.is_active = sqlc.narg('is_active')::boolean)
  AND technicians.deleted_at IS NULL AND users.deleted_at IS NULL
ORDER BY technicians.created_at, technicians.technician_id
LIMIT sqlc.arg('limit') OFFSET sqlc.arg('offset');

-- name: UpdateTechnicianForDealership :one
WITH updated_user AS (
  UPDATE appointment_scheduler.users SET name = sqlc.arg('name'), phone = sqlc.arg('phone'),
    email = sqlc.narg('email'), is_active = sqlc.arg('is_active'), updated_at = sqlc.arg('updated_at')
  WHERE user_id = (
    SELECT user_id FROM appointment_scheduler.technicians
    WHERE appointment_scheduler.technicians.technician_id = sqlc.arg('technician_id')
      AND appointment_scheduler.technicians.deleted_at IS NULL
  ) AND dealership_id = sqlc.arg('dealership_id') AND deleted_at IS NULL
  RETURNING user_id, name, phone, email
), updated_technician AS (
  UPDATE appointment_scheduler.technicians SET is_active = sqlc.arg('is_active'), updated_at = sqlc.arg('updated_at')
  WHERE technician_id = sqlc.arg('technician_id') AND user_id IN (SELECT user_id FROM updated_user)
  RETURNING technician_id, user_id, is_active, created_at, updated_at
)
SELECT updated_technician.technician_id, updated_technician.user_id, updated_user.name,
  updated_user.phone, updated_user.email, updated_technician.is_active,
  updated_technician.created_at, updated_technician.updated_at
FROM updated_technician JOIN updated_user USING (user_id);

-- name: HasFutureActiveTechnicianAppointments :one
SELECT EXISTS (
  SELECT 1 FROM appointment_scheduler.appointments
  WHERE technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL
    AND status IN ('requested', 'checked_in', 'in_progress') AND ends_at > sqlc.arg('now')
);

-- name: DeactivateTechnicianForDealership :execrows
UPDATE appointment_scheduler.technicians SET is_active = FALSE, updated_at = sqlc.arg('updated_at')
WHERE technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL
  AND user_id IN (
    SELECT user_id FROM appointment_scheduler.users
    WHERE dealership_id = sqlc.arg('dealership_id') AND deleted_at IS NULL
  );

-- name: GetTechnicians :one
SELECT technician_id, user_id, is_active, created_at, updated_at, deleted_at
FROM appointment_scheduler.technicians
WHERE technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL;

-- name: CreateTechnicians :exec
INSERT INTO appointment_scheduler.technicians (technician_id, user_id, is_active, created_at, updated_at)
VALUES (sqlc.arg('technician_id'), sqlc.arg('user_id'), sqlc.arg('is_active'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateTechnicians :execrows
UPDATE appointment_scheduler.technicians
SET user_id = sqlc.arg('user_id'), is_active = sqlc.arg('is_active'), updated_at = sqlc.arg('updated_at')
WHERE technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL;

-- name: DeleteTechnicians :execrows
UPDATE appointment_scheduler.technicians
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE technician_id = sqlc.arg('technician_id') AND deleted_at IS NULL;
