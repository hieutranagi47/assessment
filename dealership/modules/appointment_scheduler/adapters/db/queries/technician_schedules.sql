-- Read-side queries for the dealership technician calendar.

-- name: CanReadTechnicianSchedules :one
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
    AND roles.deleted_at IS NULL
    AND roles.code IN ('admin', 'staff', 'dealer')
);

-- name: GetActiveTechnicianScheduleDealership :one
SELECT dealership_id, timezone
FROM appointment_scheduler.dealerships
WHERE dealership_id = sqlc.arg('dealership_id')
  AND is_active
  AND deleted_at IS NULL;

-- name: ListActiveTechniciansForSchedule :many
SELECT technicians.technician_id, technicians.user_id, users.name
FROM appointment_scheduler.technicians AS technicians
JOIN appointment_scheduler.users AS users ON users.user_id = technicians.user_id
WHERE users.dealership_id = sqlc.arg('dealership_id')
  AND technicians.is_active
  AND technicians.deleted_at IS NULL
  AND users.deleted_at IS NULL
  AND (sqlc.narg('technician_id')::uuid IS NULL OR technicians.technician_id = sqlc.narg('technician_id')::uuid)
ORDER BY technicians.created_at, technicians.technician_id;

-- name: ListTechnicianScheduleShifts :many
SELECT shifts.technician_id, shifts.starts_at, shifts.ends_at
FROM appointment_scheduler.technician_shifts AS shifts
JOIN appointment_scheduler.technicians AS technicians ON technicians.technician_id = shifts.technician_id
JOIN appointment_scheduler.users AS users ON users.user_id = technicians.user_id
WHERE users.dealership_id = sqlc.arg('dealership_id')
  AND technicians.is_active
  AND technicians.deleted_at IS NULL
  AND users.deleted_at IS NULL
  AND shifts.deleted_at IS NULL
  AND shifts.day_of_week = sqlc.arg('day_of_week')
  AND (sqlc.narg('technician_id')::uuid IS NULL OR shifts.technician_id = sqlc.narg('technician_id')::uuid)
ORDER BY shifts.technician_id, shifts.starts_at, shifts.ends_at;

-- name: ListTechnicianScheduleAppointments :many
SELECT appointments.technician_id, appointments.appointment_id, appointments.reference_code,
  appointments.starts_at, appointments.ends_at, appointments.status, service_types.name AS service_type_name,
  service_bays.service_bay_id, service_bays.code AS service_bay_code
FROM appointment_scheduler.appointments AS appointments
JOIN appointment_scheduler.technicians AS technicians ON technicians.technician_id = appointments.technician_id
JOIN appointment_scheduler.users AS users ON users.user_id = technicians.user_id
JOIN appointment_scheduler.service_types AS service_types ON service_types.service_type_id = appointments.service_type_id
JOIN appointment_scheduler.service_bays AS service_bays ON service_bays.service_bay_id = appointments.service_bay_id
WHERE appointments.dealership_id = sqlc.arg('dealership_id')
  AND users.dealership_id = sqlc.arg('dealership_id')
  AND technicians.is_active
  AND technicians.deleted_at IS NULL
  AND users.deleted_at IS NULL
  AND appointments.deleted_at IS NULL
  AND appointments.status IN ('requested', 'checked_in', 'in_progress')
  AND appointments.starts_at < sqlc.arg('period_ends_at')
  AND appointments.ends_at > sqlc.arg('period_starts_at')
  AND (sqlc.narg('technician_id')::uuid IS NULL OR appointments.technician_id = sqlc.narg('technician_id')::uuid)
ORDER BY appointments.technician_id, appointments.starts_at, appointments.ends_at, appointments.appointment_id;

-- name: ListTechnicianScheduleTimeOff :many
SELECT time_off.technician_id, time_off.starts_at, time_off.ends_at
FROM appointment_scheduler.technician_time_off AS time_off
JOIN appointment_scheduler.technicians AS technicians ON technicians.technician_id = time_off.technician_id
JOIN appointment_scheduler.users AS users ON users.user_id = technicians.user_id
WHERE users.dealership_id = sqlc.arg('dealership_id')
  AND technicians.is_active
  AND technicians.deleted_at IS NULL
  AND users.deleted_at IS NULL
  AND time_off.deleted_at IS NULL
  AND time_off.starts_at < sqlc.arg('period_ends_at')
  AND time_off.ends_at > sqlc.arg('period_starts_at')
  AND (sqlc.narg('technician_id')::uuid IS NULL OR time_off.technician_id = sqlc.narg('technician_id')::uuid)
ORDER BY time_off.technician_id, time_off.starts_at, time_off.ends_at, time_off.technician_time_off_id;
