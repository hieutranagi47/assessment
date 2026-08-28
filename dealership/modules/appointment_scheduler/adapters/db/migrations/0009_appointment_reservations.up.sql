-- Reservations, rather than the mutable appointment row, own capacity.  This
-- preserves the original slot and makes a check-in reassignment auditable.
ALTER TABLE appointment_scheduler.appointments
  ADD COLUMN planned_duration_minutes INTEGER,
  ADD COLUMN actual_ends_at TIMESTAMPTZ,
  ADD COLUMN in_progress_at TIMESTAMPTZ;

ALTER TABLE appointment_scheduler.appointments
  ADD CONSTRAINT appointments_planned_duration_positive
    CHECK (planned_duration_minutes IS NULL OR planned_duration_minutes > 0);

CREATE TABLE appointment_scheduler.appointment_resource_reservations (
  appointment_resource_reservation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id UUID NOT NULL REFERENCES appointment_scheduler.appointments(appointment_id),
  resource_type VARCHAR(32) NOT NULL,
  resource_id UUID NOT NULL,
  reserved_starts_at TIMESTAMPTZ NOT NULL,
  reserved_ends_at TIMESTAMPTZ NOT NULL,
  status VARCHAR(32) NOT NULL,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  released_at TIMESTAMPTZ,
  assigned_by_user_id UUID NOT NULL REFERENCES appointment_scheduler.users(user_id),
  reason TEXT,
  CONSTRAINT appointment_resource_reservations_type_check
    CHECK (resource_type IN ('technician', 'service_bay')),
  CONSTRAINT appointment_resource_reservations_status_check
    CHECK (status IN ('requested', 'checked_in', 'in_progress', 'completed', 'cancelled')),
  CONSTRAINT appointment_resource_reservations_interval_check
    CHECK (reserved_ends_at > reserved_starts_at)
);

CREATE INDEX appointment_resource_reservations_appointment_id_idx
  ON appointment_scheduler.appointment_resource_reservations (appointment_id, assigned_at);

ALTER TABLE appointment_scheduler.appointment_resource_reservations
  ADD CONSTRAINT appointment_resource_reservations_no_overlap
  EXCLUDE USING gist (
    resource_type WITH =,
    resource_id WITH =,
    tstzrange(reserved_starts_at, reserved_ends_at, '[)') WITH &&
  ) WHERE (
    released_at IS NULL
    AND status IN ('requested', 'checked_in', 'in_progress')
  );

-- Keep legacy appointment constraints during rollout; capacity writes use the
-- reservation constraint above, which also permits adjacent [start, end) slots.
ALTER TABLE appointment_scheduler.appointment_audit_events
  DROP COLUMN deleted_at;

CREATE OR REPLACE FUNCTION appointment_scheduler.prevent_appointment_audit_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'appointment audit events are append-only';
END;
$$;

CREATE TRIGGER appointment_audit_events_append_only
  BEFORE UPDATE OR DELETE ON appointment_scheduler.appointment_audit_events
  FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.prevent_appointment_audit_mutation();
