-- Replace the legacy free-text, soft-deleted skill records with the shared
-- normalized skill catalog used by service type requirements.
INSERT INTO appointment_scheduler.skills (skill_id, code, name)
SELECT gen_random_uuid(), legacy.skill_code, legacy.skill_code
FROM (
  SELECT DISTINCT skill_code
  FROM appointment_scheduler.technician_skills
) AS legacy
ON CONFLICT (code) DO NOTHING;

ALTER TABLE appointment_scheduler.skills
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE appointment_scheduler.technician_skills
  ADD COLUMN skill_id UUID;

UPDATE appointment_scheduler.technician_skills technician_skill
SET skill_id = skills.skill_id
FROM appointment_scheduler.skills
WHERE skills.code = technician_skill.skill_code;

ALTER TABLE appointment_scheduler.technician_skills
  ALTER COLUMN skill_id SET NOT NULL,
  ADD CONSTRAINT technician_skills_skill_id_fkey
    FOREIGN KEY (skill_id)
    REFERENCES appointment_scheduler.skills(skill_id),
  DROP CONSTRAINT technician_skills_unique,
  DROP COLUMN skill_code,
  DROP COLUMN expires_at,
  DROP COLUMN deleted_at,
  ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD CONSTRAINT technician_skills_technician_skill_unique
    UNIQUE (technician_id, skill_id);

CREATE INDEX technician_skills_technician_id_idx
  ON appointment_scheduler.technician_skills (technician_id);
