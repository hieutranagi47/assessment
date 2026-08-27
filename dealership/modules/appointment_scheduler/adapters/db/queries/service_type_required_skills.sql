-- Required skills are always selected through their dealership-owned service type.

-- name: SkillExists :one
SELECT EXISTS(
  SELECT 1
  FROM appointment_scheduler.skills
  WHERE skill_id = sqlc.arg('skill_id')
);

-- name: CreateServiceTypeRequiredSkill :one
INSERT INTO appointment_scheduler.service_type_required_skills (service_type_required_skill_id, service_type_id, skill_id, created_at, updated_at)
SELECT sqlc.arg('service_type_required_skill_id'), service_types.service_type_id,
  skills.skill_id, sqlc.arg('created_at'), sqlc.arg('updated_at')
FROM appointment_scheduler.service_types
JOIN appointment_scheduler.skills ON skills.skill_id = sqlc.arg('skill_id')
WHERE service_types.service_type_id = sqlc.arg('service_type_id')
  AND service_types.dealership_id = sqlc.arg('dealership_id')
  AND service_types.deleted_at IS NULL
RETURNING service_type_required_skill_id, service_type_id, skill_id, created_at, updated_at;

-- name: GetServiceTypeRequiredSkill :one
SELECT required_skill.service_type_required_skill_id, required_skill.service_type_id,
  skills.skill_id, skills.code, skills.name, required_skill.created_at, required_skill.updated_at
FROM appointment_scheduler.service_type_required_skills required_skill
JOIN appointment_scheduler.service_types service_types ON service_types.service_type_id = required_skill.service_type_id
JOIN appointment_scheduler.skills skills ON skills.skill_id = required_skill.skill_id
WHERE required_skill.service_type_required_skill_id = sqlc.arg('service_type_required_skill_id')
  AND required_skill.service_type_id = sqlc.arg('service_type_id')
  AND service_types.dealership_id = sqlc.arg('dealership_id')
  AND service_types.deleted_at IS NULL;

-- name: ListServiceTypeRequiredSkills :many
SELECT required_skill.service_type_required_skill_id, required_skill.service_type_id,
  skills.skill_id, skills.code, skills.name, required_skill.created_at, required_skill.updated_at
FROM appointment_scheduler.service_type_required_skills required_skill
JOIN appointment_scheduler.service_types service_types ON service_types.service_type_id = required_skill.service_type_id
JOIN appointment_scheduler.skills skills ON skills.skill_id = required_skill.skill_id
WHERE required_skill.service_type_id = sqlc.arg('service_type_id')
  AND service_types.dealership_id = sqlc.arg('dealership_id')
  AND service_types.deleted_at IS NULL
ORDER BY skills.name, skills.skill_id;

-- name: UpdateServiceTypeRequiredSkill :one
UPDATE appointment_scheduler.service_type_required_skills required_skill
SET skill_id = sqlc.arg('skill_id'), updated_at = sqlc.arg('updated_at')
FROM appointment_scheduler.service_types service_types
WHERE required_skill.service_type_required_skill_id = sqlc.arg('service_type_required_skill_id')
  AND required_skill.service_type_id = sqlc.arg('service_type_id')
  AND service_types.service_type_id = required_skill.service_type_id
  AND service_types.dealership_id = sqlc.arg('dealership_id')
  AND service_types.deleted_at IS NULL
RETURNING required_skill.service_type_required_skill_id, required_skill.service_type_id,
  required_skill.skill_id, required_skill.created_at, required_skill.updated_at;

-- name: DeleteServiceTypeRequiredSkill :execrows
DELETE FROM appointment_scheduler.service_type_required_skills required_skill
USING appointment_scheduler.service_types service_types
WHERE required_skill.service_type_required_skill_id = sqlc.arg('service_type_required_skill_id')
  AND required_skill.service_type_id = sqlc.arg('service_type_id')
  AND service_types.service_type_id = required_skill.service_type_id
  AND service_types.dealership_id = sqlc.arg('dealership_id')
  AND service_types.deleted_at IS NULL;
