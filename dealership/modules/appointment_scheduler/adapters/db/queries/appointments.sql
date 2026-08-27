-- appointments CRUD queries.

-- name: GetAppointments :one
SELECT appointment_id, reference_code, customer_id, vehicle_id, dealership_id, service_type_id, technician_id, service_bay_id, starts_at, ends_at, status, notes, created_by_user_id, cancelled_by_user_id, cancellation_reason, created_at, updated_at, cancelled_at, checked_in_at, started_at, completed_at, deleted_at
FROM appointment_scheduler.appointments
WHERE appointment_id = sqlc.arg('appointment_id') AND deleted_at IS NULL;

-- name: CreateAppointments :exec
INSERT INTO appointment_scheduler.appointments (appointment_id, reference_code, customer_id, vehicle_id, dealership_id, service_type_id, technician_id, service_bay_id, starts_at, ends_at, status, notes, created_by_user_id, cancelled_by_user_id, cancellation_reason, created_at, updated_at, cancelled_at, checked_in_at, started_at, completed_at)
VALUES (sqlc.narg('appointment_id'), sqlc.arg('reference_code'), sqlc.arg('customer_id'), sqlc.arg('vehicle_id'), sqlc.arg('dealership_id'), sqlc.arg('service_type_id'), sqlc.arg('technician_id'), sqlc.arg('service_bay_id'), sqlc.arg('starts_at'), sqlc.arg('ends_at'), sqlc.arg('status'), sqlc.narg('notes'), sqlc.arg('created_by_user_id'), sqlc.narg('cancelled_by_user_id'), sqlc.narg('cancellation_reason'), sqlc.arg('created_at'), sqlc.arg('updated_at'), sqlc.narg('cancelled_at'), sqlc.narg('checked_in_at'), sqlc.narg('started_at'), sqlc.narg('completed_at'));

-- name: UpdateAppointments :execrows
UPDATE appointment_scheduler.appointments
SET reference_code = sqlc.arg('reference_code'), customer_id = sqlc.arg('customer_id'), vehicle_id = sqlc.arg('vehicle_id'), dealership_id = sqlc.arg('dealership_id'), service_type_id = sqlc.arg('service_type_id'), technician_id = sqlc.arg('technician_id'), service_bay_id = sqlc.arg('service_bay_id'), starts_at = sqlc.arg('starts_at'), ends_at = sqlc.arg('ends_at'), status = sqlc.arg('status'), notes = sqlc.narg('notes'), created_by_user_id = sqlc.arg('created_by_user_id'), cancelled_by_user_id = sqlc.narg('cancelled_by_user_id'), cancellation_reason = sqlc.narg('cancellation_reason'), updated_at = sqlc.arg('updated_at'), cancelled_at = sqlc.narg('cancelled_at'), checked_in_at = sqlc.narg('checked_in_at'), started_at = sqlc.narg('started_at'), completed_at = sqlc.narg('completed_at')
WHERE appointment_id = sqlc.arg('appointment_id') AND deleted_at IS NULL;

-- name: DeleteAppointments :execrows
UPDATE appointment_scheduler.appointments
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE appointment_id = sqlc.arg('appointment_id') AND deleted_at IS NULL;

