-- technician skills CRUD queries.

-- name: GetTechnicianSkills :one
SELECT technician_skill_id, technician_id, skill_code, expires_at, created_at, deleted_at
FROM appointment_scheduler.technician_skills
WHERE technician_skill_id = sqlc.arg('technician_skill_id') AND deleted_at IS NULL;

-- name: CreateTechnicianSkills :exec
INSERT INTO appointment_scheduler.technician_skills (technician_skill_id, technician_id, skill_code, expires_at, created_at)
VALUES (sqlc.arg('technician_skill_id'), sqlc.arg('technician_id'), sqlc.arg('skill_code'), sqlc.narg('expires_at'), sqlc.arg('created_at'));

-- name: UpdateTechnicianSkills :execrows
UPDATE appointment_scheduler.technician_skills
SET technician_id = sqlc.arg('technician_id'), skill_code = sqlc.arg('skill_code'), expires_at = sqlc.narg('expires_at')
WHERE technician_skill_id = sqlc.arg('technician_skill_id') AND deleted_at IS NULL;

-- name: DeleteTechnicianSkills :execrows
UPDATE appointment_scheduler.technician_skills
SET deleted_at = sqlc.arg('deleted_at')::timestamptz
WHERE technician_skill_id = sqlc.arg('technician_skill_id') AND deleted_at IS NULL;

