CREATE TABLE appointment_scheduler.skills (
  skill_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(100) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO appointment_scheduler.skills (code, name)
SELECT DISTINCT skill_code, skill_code
FROM appointment_scheduler.service_type_required_skills
ON CONFLICT (code) DO NOTHING;

ALTER TABLE appointment_scheduler.service_type_required_skills
  ADD COLUMN skill_id UUID;

UPDATE appointment_scheduler.service_type_required_skills required_skill
SET skill_id = skills.skill_id
FROM appointment_scheduler.skills skills
WHERE skills.code = required_skill.skill_code;

ALTER TABLE appointment_scheduler.service_type_required_skills
  ALTER COLUMN skill_id SET NOT NULL,
  ADD CONSTRAINT service_type_required_skills_skill_id_fkey
    FOREIGN KEY (skill_id) REFERENCES appointment_scheduler.skills(skill_id),
  ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  DROP CONSTRAINT service_type_required_skills_unique,
  DROP COLUMN skill_code,
  DROP COLUMN deleted_at,
  ADD CONSTRAINT service_type_required_skills_service_type_skill_unique
    UNIQUE (service_type_id, skill_id);
