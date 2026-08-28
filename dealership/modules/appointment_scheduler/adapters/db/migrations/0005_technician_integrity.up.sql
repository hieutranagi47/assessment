CREATE UNIQUE INDEX technicians_dealership_phone_unique
  ON appointment_scheduler.users (dealership_id, phone)
  WHERE auth_user_id = '00000000-0000-0000-0000-000000000000'
    AND phone IS NOT NULL
    AND deleted_at IS NULL;

CREATE UNIQUE INDEX technicians_dealership_email_unique
  ON appointment_scheduler.users (dealership_id, lower(email))
  WHERE auth_user_id = '00000000-0000-0000-0000-000000000000'
    AND email IS NOT NULL
    AND deleted_at IS NULL;

CREATE INDEX appointments_active_future_technician_idx
  ON appointment_scheduler.appointments (technician_id, ends_at)
  WHERE deleted_at IS NULL
    AND status IN ('requested', 'checked_in', 'in_progress');

CREATE OR REPLACE FUNCTION appointment_scheduler.enforce_technician_user_integrity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME = 'technicians' THEN
    IF EXISTS (
      SELECT 1 FROM appointment_scheduler.users
      WHERE user_id = NEW.user_id
        AND auth_user_id <> '00000000-0000-0000-0000-000000000000'
    ) THEN
      RAISE EXCEPTION 'technician users cannot have a login identity';
    END IF;
    IF EXISTS (SELECT 1 FROM appointment_scheduler.user_roles WHERE user_id = NEW.user_id) THEN
      RAISE EXCEPTION 'technician users cannot have roles';
    END IF;
  ELSIF TG_TABLE_NAME = 'user_roles' AND EXISTS (
    SELECT 1 FROM appointment_scheduler.technicians
    WHERE user_id = NEW.user_id AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'technician users cannot have roles';
  ELSIF TG_TABLE_NAME = 'users' AND NEW.auth_user_id <> '00000000-0000-0000-0000-000000000000'
    AND EXISTS (SELECT 1 FROM appointment_scheduler.technicians WHERE user_id = NEW.user_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'technician users cannot have a login identity';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER technicians_enforce_user_integrity
  BEFORE INSERT OR UPDATE OF user_id ON appointment_scheduler.technicians
  FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.enforce_technician_user_integrity();
CREATE TRIGGER user_roles_enforce_technician_integrity
  BEFORE INSERT OR UPDATE OF user_id ON appointment_scheduler.user_roles
  FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.enforce_technician_user_integrity();
CREATE TRIGGER users_enforce_technician_integrity
  BEFORE UPDATE OF auth_user_id ON appointment_scheduler.users
  FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.enforce_technician_user_integrity();
