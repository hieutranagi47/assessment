ALTER TABLE appointment_scheduler.service_type_required_skills
  DROP CONSTRAINT service_type_required_skills_service_type_skill_unique,
  ADD COLUMN skill_code VARCHAR(100),
  ADD COLUMN deleted_at TIMESTAMPTZ,
  DROP COLUMN updated_at,
  DROP CONSTRAINT service_type_required_skills_skill_id_fkey;

UPDATE appointment_scheduler.service_type_required_skills required_skill
SET skill_code = skills.code
FROM appointment_scheduler.skills skills
WHERE skills.skill_id = required_skill.skill_id;

ALTER TABLE appointment_scheduler.service_type_required_skills
  ALTER COLUMN skill_code SET NOT NULL,
  DROP COLUMN skill_id,
  ADD CONSTRAINT service_type_required_skills_unique UNIQUE (service_type_id, skill_code);

DROP TABLE appointment_scheduler.skills;
