-- dealership operation time CRUD queries.

-- name: GetDealershipOperationTime :one
SELECT dealership_operation_time_id, dealership_id, day_of_week, opens_at, closes_at, created_at, updated_at
FROM appointment_scheduler.dealership_operation_time
WHERE dealership_id = sqlc.arg('dealership_id')
  AND dealership_operation_time_id = sqlc.arg('dealership_operation_time_id');

-- name: ListDealershipOperationTimes :many
SELECT dealership_operation_time_id, dealership_id, day_of_week, opens_at, closes_at, created_at, updated_at
FROM appointment_scheduler.dealership_operation_time
WHERE dealership_id = sqlc.arg('dealership_id')
ORDER BY day_of_week, opens_at;

-- name: CreateDealershipOperationTime :exec
INSERT INTO appointment_scheduler.dealership_operation_time (dealership_operation_time_id, dealership_id, day_of_week, opens_at, closes_at, created_at, updated_at)
VALUES (sqlc.arg('dealership_operation_time_id'), sqlc.arg('dealership_id'), sqlc.arg('day_of_week'), sqlc.arg('opens_at'), sqlc.arg('closes_at'), sqlc.arg('created_at'), sqlc.arg('updated_at'));

-- name: UpdateDealershipOperationTime :execrows
UPDATE appointment_scheduler.dealership_operation_time
SET dealership_id = sqlc.arg('dealership_id'), day_of_week = sqlc.arg('day_of_week'), opens_at = sqlc.arg('opens_at'), closes_at = sqlc.arg('closes_at'), updated_at = sqlc.arg('updated_at')
WHERE dealership_id = sqlc.arg('dealership_id')
  AND dealership_operation_time_id = sqlc.arg('dealership_operation_time_id');

-- name: DeleteDealershipOperationTime :execrows
DELETE FROM appointment_scheduler.dealership_operation_time
WHERE dealership_id = sqlc.arg('dealership_id')
  AND dealership_operation_time_id = sqlc.arg('dealership_operation_time_id');
