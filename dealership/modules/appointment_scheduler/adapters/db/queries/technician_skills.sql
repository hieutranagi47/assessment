-- Technician skills are scoped by technician ID so nested resources cannot
-- cross technician boundaries.

-- name: GetActiveTechnician :one
SELECT technician_id
FROM appointment_scheduler.technicians
WHERE technician_id = sqlc.arg('technician_id')
  AND is_active = TRUE
  AND deleted_at IS NULL;

-- name: ActiveSkillExists :one
SELECT EXISTS(
  SELECT 1
  FROM appointment_scheduler.skills
  WHERE skill_id = sqlc.arg('skill_id')
    AND is_active = TRUE
);

-- name: CreateTechnicianSkill :one
INSERT INTO appointment_scheduler.technician_skills (technician_skill_id, technician_id, skill_id, created_at, updated_at)
SELECT sqlc.arg('technician_skill_id'), technicians.technician_id, skills.skill_id,
  sqlc.arg('created_at'), sqlc.arg('updated_at')
FROM appointment_scheduler.technicians
JOIN appointment_scheduler.skills ON skills.skill_id = sqlc.arg('skill_id')
WHERE technicians.technician_id = sqlc.arg('technician_id')
  AND technicians.is_active = TRUE
  AND technicians.deleted_at IS NULL
  AND skills.is_active = TRUE
RETURNING technician_skill_id, technician_id, skill_id, created_at, updated_at;

-- name: GetTechnicianSkill :one
SELECT technician_skill.technician_skill_id, technician_skill.technician_id,
  technician_skill.skill_id, technician_skill.created_at, technician_skill.updated_at
FROM appointment_scheduler.technician_skills technician_skill
JOIN appointment_scheduler.technicians ON technicians.technician_id = technician_skill.technician_id
WHERE technician_skill.technician_skill_id = sqlc.arg('technician_skill_id')
  AND technician_skill.technician_id = sqlc.arg('technician_id')
  AND technicians.is_active = TRUE
  AND technicians.deleted_at IS NULL;

-- name: ListTechnicianSkills :many
SELECT technician_skill_id, technician_id, skill_id, created_at, updated_at
FROM appointment_scheduler.technician_skills
WHERE technician_id = sqlc.arg('technician_id')
ORDER BY created_at, technician_skill_id;

-- name: UpdateTechnicianSkill :one
UPDATE appointment_scheduler.technician_skills technician_skill
SET skill_id = skills.skill_id, updated_at = sqlc.arg('updated_at')
FROM appointment_scheduler.technicians
JOIN appointment_scheduler.skills ON skills.skill_id = sqlc.arg('skill_id')
WHERE technician_skill.technician_skill_id = sqlc.arg('technician_skill_id')
  AND technician_skill.technician_id = sqlc.arg('technician_id')
  AND technicians.technician_id = technician_skill.technician_id
  AND technicians.is_active = TRUE
  AND technicians.deleted_at IS NULL
  AND skills.is_active = TRUE
RETURNING technician_skill.technician_skill_id, technician_skill.technician_id,
  technician_skill.skill_id, technician_skill.created_at, technician_skill.updated_at;

-- name: DeleteTechnicianSkill :execrows
DELETE FROM appointment_scheduler.technician_skills
WHERE technician_skill_id = sqlc.arg('technician_skill_id')
  AND technician_id = sqlc.arg('technician_id');
