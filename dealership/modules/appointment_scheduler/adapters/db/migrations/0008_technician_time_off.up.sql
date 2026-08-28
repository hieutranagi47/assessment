ALTER TABLE appointment_scheduler.technician_time_off
  ADD COLUMN created_by_user_id UUID REFERENCES appointment_scheduler.users(user_id),
  ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Existing installations may already contain legacy rows. Attribute them to
-- the technician's scheduler user before making the audit column mandatory.
UPDATE appointment_scheduler.technician_time_off AS time_off
SET created_by_user_id = technicians.user_id
FROM appointment_scheduler.technicians AS technicians
WHERE technicians.technician_id = time_off.technician_id
  AND time_off.created_by_user_id IS NULL;

ALTER TABLE appointment_scheduler.technician_time_off
  ALTER COLUMN created_by_user_id SET NOT NULL;

ALTER TABLE appointment_scheduler.technician_time_off
  ADD CONSTRAINT technician_time_off_no_overlap
  EXCLUDE USING gist (
    technician_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) WHERE (deleted_at IS NULL);

-- Appointment writes must participate in the same technician-scoped lock as
-- time-off writes. This protects direct SQL scheduling paths as well as future
-- application handlers from a create/reschedule race.
CREATE OR REPLACE FUNCTION appointment_scheduler.reject_appointment_during_time_off()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.deleted_at IS NULL
     AND NEW.status IN ('requested', 'checked_in', 'in_progress') THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.technician_id::text, 0));
    IF EXISTS (
      SELECT 1
      FROM appointment_scheduler.technician_time_off
      WHERE technician_id = NEW.technician_id
        AND deleted_at IS NULL
        AND starts_at < NEW.ends_at
        AND ends_at > NEW.starts_at
    ) THEN
      RAISE EXCEPTION 'appointment overlaps technician time off'
        USING ERRCODE = '23P01', CONSTRAINT = 'appointments_no_technician_time_off';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER appointments_reject_technician_time_off
BEFORE INSERT OR UPDATE OF technician_id, starts_at, ends_at, status, deleted_at
ON appointment_scheduler.appointments
FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.reject_appointment_during_time_off();
