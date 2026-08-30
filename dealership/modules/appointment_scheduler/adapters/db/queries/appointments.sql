-- appointments CRUD queries.

-- name: GetActiveDealershipTimezone :one
SELECT timezone
FROM appointment_scheduler.dealerships
WHERE dealership_id = sqlc.arg('dealership_id')
  AND is_active
  AND deleted_at IS NULL;

-- name: GetActiveServiceTypeDuration :one
SELECT min_duration_minutes, max_duration_minutes
FROM appointment_scheduler.service_types
WHERE service_type_id = sqlc.arg('service_type_id')
  AND dealership_id = sqlc.arg('dealership_id')
  AND is_active
  AND deleted_at IS NULL;

-- name: CustomerVehicleBelongsToDealership :one
SELECT EXISTS (
  SELECT 1
  FROM appointment_scheduler.customer_dealerships cd
  JOIN appointment_scheduler.vehicles v
    ON v.customer_id = cd.customer_id
   AND v.vehicle_id = sqlc.arg('vehicle_id')
   AND v.deleted_at IS NULL
  WHERE cd.customer_id = sqlc.arg('customer_id')
    AND cd.dealership_id = sqlc.arg('dealership_id')
);

-- name: IsWithinDealershipOperatingHours :one
SELECT EXISTS (
  SELECT 1
  FROM appointment_scheduler.dealership_operation_time ot
  WHERE ot.dealership_id = sqlc.arg('dealership_id')
    AND ot.day_of_week = EXTRACT(ISODOW FROM sqlc.arg('starts_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::smallint
    AND (sqlc.arg('starts_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::date = (sqlc.arg('ends_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::date
    AND (sqlc.arg('starts_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::time >= ot.opens_at
    AND (sqlc.arg('ends_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::time <= ot.closes_at
);

-- name: IsCompatibleTechnician :one
SELECT EXISTS (
  SELECT 1
  FROM appointment_scheduler.technicians t
  JOIN appointment_scheduler.users u ON u.user_id = t.user_id
  WHERE t.technician_id = sqlc.arg('technician_id')
    AND u.dealership_id = sqlc.arg('dealership_id')
    AND t.is_active
    AND t.deleted_at IS NULL
    AND u.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM appointment_scheduler.service_type_required_skills required
      WHERE required.service_type_id = sqlc.arg('service_type_id')
        AND NOT EXISTS (
          SELECT 1
          FROM appointment_scheduler.technician_skills skill
          WHERE skill.technician_id = t.technician_id
            AND skill.skill_id = required.skill_id
        )
    )
);

-- name: IsCompatibleServiceBay :one
SELECT EXISTS (
  SELECT 1
  FROM appointment_scheduler.service_bays b
  WHERE b.service_bay_id = sqlc.arg('service_bay_id')
    AND b.dealership_id = sqlc.arg('dealership_id')
    AND b.is_active
    AND b.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM appointment_scheduler.service_type_required_bay_capabilities required
      WHERE required.service_type_id = sqlc.arg('service_type_id')
        AND NOT EXISTS (
          SELECT 1
          FROM appointment_scheduler.service_bay_capabilities capability
          WHERE capability.service_bay_id = b.service_bay_id
            AND capability.bay_capability_id = required.bay_capability_id
        )
    )
);

-- name: IsTechnicianAvailableForAppointment :one
SELECT EXISTS (
  SELECT 1
  FROM appointment_scheduler.technician_shifts s
  WHERE s.technician_id = sqlc.arg('technician_id')
    AND s.deleted_at IS NULL
    AND s.day_of_week = EXTRACT(ISODOW FROM sqlc.arg('starts_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::smallint
    AND (sqlc.arg('starts_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::date = (sqlc.arg('ends_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::date
    AND (sqlc.arg('starts_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::time >= s.starts_at
    AND (sqlc.arg('ends_at')::timestamptz AT TIME ZONE sqlc.arg('timezone')::text)::time <= s.ends_at
)
AND NOT EXISTS (
  SELECT 1
  FROM appointment_scheduler.technician_time_off t
  WHERE t.technician_id = sqlc.arg('technician_id')
    AND t.deleted_at IS NULL
    AND t.starts_at < sqlc.arg('ends_at')::timestamptz
    AND t.ends_at > sqlc.arg('starts_at')::timestamptz
);

-- name: CreateScheduledAppointment :exec
INSERT INTO appointment_scheduler.appointments (
  appointment_id, reference_code, customer_id, vehicle_id, dealership_id,
  service_type_id, technician_id, service_bay_id, starts_at, ends_at,
  planned_duration_minutes, status, notes, created_by_user_id, created_at,
  updated_at
)
VALUES (
  sqlc.arg('appointment_id'), sqlc.arg('reference_code'), sqlc.arg('customer_id'),
  sqlc.arg('vehicle_id'), sqlc.arg('dealership_id'), sqlc.arg('service_type_id'),
  sqlc.arg('technician_id'), sqlc.arg('service_bay_id'), sqlc.arg('starts_at'),
  sqlc.arg('ends_at'), sqlc.arg('planned_duration_minutes'), 'requested',
  sqlc.narg('notes'), sqlc.arg('created_by_user_id'), sqlc.arg('created_at'),
  sqlc.arg('updated_at')
);

-- name: GetAppointmentForTransition :one
SELECT status, starts_at, ends_at, notes
FROM appointment_scheduler.appointments
WHERE appointment_id = sqlc.arg('appointment_id')
  AND dealership_id = sqlc.arg('dealership_id')
  AND deleted_at IS NULL
FOR UPDATE;

-- name: GetAppointmentCheckedInAt :one
SELECT checked_in_at
FROM appointment_scheduler.appointments
WHERE appointment_id = sqlc.arg('appointment_id');

-- name: CheckInAppointment :exec
UPDATE appointment_scheduler.appointments
SET status = 'checked_in', checked_in_at = sqlc.arg('occurred_at'), notes = sqlc.narg('notes'), updated_at = sqlc.arg('occurred_at')
WHERE appointment_id = sqlc.arg('appointment_id');

-- name: StartAppointment :exec
UPDATE appointment_scheduler.appointments
SET status = 'in_progress', in_progress_at = sqlc.arg('occurred_at'), started_at = sqlc.arg('occurred_at'), notes = sqlc.narg('notes'), updated_at = sqlc.arg('occurred_at')
WHERE appointment_id = sqlc.arg('appointment_id');

-- name: CompleteAppointment :exec
UPDATE appointment_scheduler.appointments
SET status = 'completed', completed_at = sqlc.arg('occurred_at'), actual_ends_at = sqlc.arg('actual_ends_at'), notes = sqlc.narg('notes'), updated_at = sqlc.arg('occurred_at')
WHERE appointment_id = sqlc.arg('appointment_id');

-- name: CancelAppointment :exec
UPDATE appointment_scheduler.appointments
SET status = 'cancelled', cancelled_at = sqlc.arg('occurred_at'), cancelled_by_user_id = sqlc.arg('actor_user_id'), cancellation_reason = sqlc.narg('cancellation_reason'), notes = sqlc.narg('notes'), updated_at = sqlc.arg('occurred_at')
WHERE appointment_id = sqlc.arg('appointment_id');

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
