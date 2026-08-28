CREATE SCHEMA IF NOT EXISTS appointment_scheduler;

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE appointment_scheduler.dealerships (
  dealership_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  code VARCHAR(50) NOT NULL UNIQUE,
  address TEXT NOT NULL,
  timezone VARCHAR(64) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE appointment_scheduler.dealership_operation_time (
  dealership_operation_time_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dealership_id UUID NOT NULL REFERENCES appointment_scheduler.dealerships(dealership_id),
  day_of_week SMALLINT NOT NULL,
  opens_at TIME NOT NULL,
  closes_at TIME NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT dealership_operation_time_day_check CHECK (day_of_week BETWEEN 1 AND 7),
  CONSTRAINT dealership_operation_time_hours_check CHECK (closes_at > opens_at),
  CONSTRAINT dealership_operation_time_no_overlap
    EXCLUDE USING gist (
      dealership_id WITH =,
      day_of_week WITH =,
      tsrange(DATE '2000-01-01' + opens_at, DATE '2000-01-01' + closes_at, '[)') WITH &&
    )
);

CREATE INDEX dealership_operation_time_dealership_day_opens_at_idx
  ON appointment_scheduler.dealership_operation_time (dealership_id, day_of_week, opens_at);

CREATE TABLE appointment_scheduler.users (
  user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
  name VARCHAR(255) NOT NULL,
  phone VARCHAR(50),
  email VARCHAR(255),
  dealership_id UUID NOT NULL REFERENCES appointment_scheduler.dealerships(dealership_id),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX users_auth_user_id_unique_when_present
  ON appointment_scheduler.users (auth_user_id)
  WHERE auth_user_id <> '00000000-0000-0000-0000-000000000000'
    AND deleted_at IS NULL;

CREATE TABLE appointment_scheduler.roles (
  role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(64) NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO appointment_scheduler.roles (role_id, code, name, description)
VALUES
  ('00000000-0000-4000-8000-000000000001', 'admin', 'Admin',
   'Full dealership configuration; creates users and technicians; manages all resources and schedules.'),
  ('00000000-0000-4000-8000-000000000002', 'staff', 'Staff',
   'Manages technician shifts, time off, and permitted technician details.'),
  ('00000000-0000-4000-8000-000000000003', 'dealer', 'Dealer',
   'Creates customers and vehicles; searches availability; creates and manages appointments.'),
  ('00000000-0000-4000-8000-000000000004', 'technician', 'Technician',
   'Manages customers and vehicles for their dealership.');

CREATE TABLE appointment_scheduler.user_roles (
  user_role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES appointment_scheduler.users(user_id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES appointment_scheduler.roles(role_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  CONSTRAINT user_roles_user_role_unique UNIQUE (user_id, role_id)
);

CREATE TABLE appointment_scheduler.customers (
  customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  phone VARCHAR(50) NOT NULL UNIQUE,
  email VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX customers_email_unique_when_present
  ON appointment_scheduler.customers (lower(email))
  WHERE email IS NOT NULL;

CREATE TABLE appointment_scheduler.customer_dealerships (
  customer_id UUID PRIMARY KEY REFERENCES appointment_scheduler.customers(customer_id),
  dealership_id UUID NOT NULL REFERENCES appointment_scheduler.dealerships(dealership_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX customer_dealerships_dealership_id_idx
  ON appointment_scheduler.customer_dealerships (dealership_id);

CREATE TABLE appointment_scheduler.vehicles (
  vehicle_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES appointment_scheduler.customers(customer_id),
  vin VARCHAR(17),
  registration_plate VARCHAR(32),
  make VARCHAR(100) NOT NULL,
  model VARCHAR(100) NOT NULL,
  model_year SMALLINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT vehicles_identity_check CHECK (vin IS NOT NULL OR registration_plate IS NOT NULL)
);

CREATE UNIQUE INDEX vehicles_vin_unique_when_present
  ON appointment_scheduler.vehicles (vin)
  WHERE vin IS NOT NULL;

CREATE TABLE appointment_scheduler.service_types (
  service_type_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dealership_id UUID NOT NULL REFERENCES appointment_scheduler.dealerships(dealership_id),
  name VARCHAR(255) NOT NULL,
  default_duration_minutes INTEGER NOT NULL,
  min_duration_minutes INTEGER NOT NULL,
  max_duration_minutes INTEGER NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT service_types_default_duration_positive CHECK (default_duration_minutes > 0),
  CONSTRAINT service_types_min_duration_positive CHECK (min_duration_minutes > 0),
  CONSTRAINT service_types_duration_range_check CHECK (max_duration_minutes >= min_duration_minutes)
);

CREATE UNIQUE INDEX service_types_dealership_name_unique
  ON appointment_scheduler.service_types (dealership_id, lower(name))
  WHERE deleted_at IS NULL;

CREATE TABLE appointment_scheduler.skills (
  skill_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(100) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE appointment_scheduler.service_type_required_skills (
  service_type_required_skill_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_type_id UUID NOT NULL REFERENCES appointment_scheduler.service_types(service_type_id) ON DELETE CASCADE,
  skill_id UUID NOT NULL REFERENCES appointment_scheduler.skills(skill_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT service_type_required_skills_service_type_skill_unique UNIQUE (service_type_id, skill_id)
);

CREATE TABLE appointment_scheduler.bay_capabilities (
  bay_capability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(100) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX bay_capabilities_code_lower_unique
  ON appointment_scheduler.bay_capabilities (lower(code));

CREATE TABLE appointment_scheduler.service_type_required_bay_capabilities (
  service_type_required_bay_capability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_type_id UUID NOT NULL REFERENCES appointment_scheduler.service_types(service_type_id) ON DELETE CASCADE,
  bay_capability_id UUID NOT NULL REFERENCES appointment_scheduler.bay_capabilities(bay_capability_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT service_type_required_bay_capabilities_service_type_bay_capability_unique
    UNIQUE (service_type_id, bay_capability_id)
);

CREATE TABLE appointment_scheduler.service_bays (
  service_bay_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dealership_id UUID NOT NULL REFERENCES appointment_scheduler.dealerships(dealership_id),
  code VARCHAR(50) NOT NULL,
  name VARCHAR(255) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX service_bays_dealership_code_lower_unique
  ON appointment_scheduler.service_bays (dealership_id, LOWER(code))
  WHERE deleted_at IS NULL;

CREATE TABLE appointment_scheduler.service_bay_capabilities (
  service_bay_capability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_bay_id UUID NOT NULL REFERENCES appointment_scheduler.service_bays(service_bay_id) ON DELETE CASCADE,
  bay_capability_id UUID NOT NULL REFERENCES appointment_scheduler.bay_capabilities(bay_capability_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT service_bay_capabilities_service_bay_bay_capability_unique
    UNIQUE (service_bay_id, bay_capability_id)
);

CREATE TABLE appointment_scheduler.technicians (
  technician_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES appointment_scheduler.users(user_id),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE appointment_scheduler.technician_skills (
  technician_skill_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  technician_id UUID NOT NULL REFERENCES appointment_scheduler.technicians(technician_id) ON DELETE CASCADE,
  skill_id UUID NOT NULL REFERENCES appointment_scheduler.skills(skill_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT technician_skills_technician_skill_unique UNIQUE (technician_id, skill_id)
);

CREATE INDEX technician_skills_technician_id_idx
  ON appointment_scheduler.technician_skills (technician_id);

CREATE TABLE appointment_scheduler.technician_shifts (
  technician_shift_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  technician_id UUID NOT NULL REFERENCES appointment_scheduler.technicians(technician_id) ON DELETE CASCADE,
  day_of_week SMALLINT NOT NULL,
  starts_at TIME NOT NULL,
  ends_at TIME NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT technician_shifts_day_check CHECK (day_of_week BETWEEN 1 AND 7),
  CONSTRAINT technician_shifts_hours_check CHECK (ends_at > starts_at),
  CONSTRAINT technician_shifts_no_overlap
    EXCLUDE USING gist (
      technician_id WITH =,
      day_of_week WITH =,
      tsrange(TIMESTAMP '2000-01-01' + starts_at, TIMESTAMP '2000-01-01' + ends_at, '[)') WITH &&
    ) WHERE (deleted_at IS NULL)
);

CREATE TABLE appointment_scheduler.technician_time_off (
  technician_time_off_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  technician_id UUID NOT NULL REFERENCES appointment_scheduler.technicians(technician_id) ON DELETE CASCADE,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  reason TEXT,
  created_by_user_id UUID NOT NULL REFERENCES appointment_scheduler.users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT technician_time_off_range_check CHECK (ends_at > starts_at),
  CONSTRAINT technician_time_off_no_overlap
    EXCLUDE USING gist (
      technician_id WITH =,
      tstzrange(starts_at, ends_at, '[)') WITH &&
    ) WHERE (deleted_at IS NULL)
);

CREATE TABLE appointment_scheduler.appointments (
  appointment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reference_code VARCHAR(50) NOT NULL UNIQUE,
  customer_id UUID NOT NULL REFERENCES appointment_scheduler.customers(customer_id),
  vehicle_id UUID NOT NULL REFERENCES appointment_scheduler.vehicles(vehicle_id),
  dealership_id UUID NOT NULL REFERENCES appointment_scheduler.dealerships(dealership_id),
  service_type_id UUID NOT NULL REFERENCES appointment_scheduler.service_types(service_type_id),
  technician_id UUID NOT NULL REFERENCES appointment_scheduler.technicians(technician_id),
  service_bay_id UUID NOT NULL REFERENCES appointment_scheduler.service_bays(service_bay_id),
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  status VARCHAR(32) NOT NULL,
  notes TEXT,
  created_by_user_id UUID NOT NULL REFERENCES appointment_scheduler.users(user_id),
  cancelled_by_user_id UUID REFERENCES appointment_scheduler.users(user_id),
  cancellation_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  cancelled_at TIMESTAMPTZ,
  checked_in_at TIMESTAMPTZ,
  in_progress_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  actual_ends_at TIMESTAMPTZ,
  planned_duration_minutes INTEGER,
  CONSTRAINT appointments_time_range_check CHECK (ends_at > starts_at),
  CONSTRAINT appointments_planned_duration_positive
    CHECK (planned_duration_minutes IS NULL OR planned_duration_minutes > 0),
  CONSTRAINT appointments_status_check CHECK (
    status IN ('requested', 'checked_in', 'in_progress', 'completed', 'cancelled')
  ),
  CONSTRAINT appointments_cancel_reason_check CHECK (
    status <> 'cancelled' OR cancellation_reason IS NOT NULL
  )
);

CREATE INDEX appointments_dealership_starts_at_idx
  ON appointment_scheduler.appointments (dealership_id, starts_at);

CREATE INDEX appointments_active_future_technician_idx
  ON appointment_scheduler.appointments (technician_id, ends_at)
  WHERE deleted_at IS NULL
    AND status IN ('requested', 'checked_in', 'in_progress');

ALTER TABLE appointment_scheduler.appointments
  ADD CONSTRAINT appointments_no_technician_overlap
  EXCLUDE USING gist (
    technician_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  )
  WHERE (status IN ('requested', 'checked_in', 'in_progress'));

ALTER TABLE appointment_scheduler.appointments
  ADD CONSTRAINT appointments_no_service_bay_overlap
  EXCLUDE USING gist (
    service_bay_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  )
  WHERE (status IN ('requested', 'checked_in', 'in_progress'));

CREATE TABLE appointment_scheduler.appointment_audit_events (
  appointment_audit_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id UUID NOT NULL REFERENCES appointment_scheduler.appointments(appointment_id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES appointment_scheduler.users(user_id),
  event_type VARCHAR(64) NOT NULL,
  before_data JSONB,
  after_data JSONB,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE appointment_scheduler.appointment_idempotency (
  idempotency_key VARCHAR(255) PRIMARY KEY,
  appointment_id UUID REFERENCES appointment_scheduler.appointments(appointment_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ
);

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
    CHECK (reserved_ends_at > reserved_starts_at),
  CONSTRAINT appointment_resource_reservations_no_overlap
    EXCLUDE USING gist (
      resource_type WITH =,
      resource_id WITH =,
      tstzrange(reserved_starts_at, reserved_ends_at, '[)') WITH &&
    ) WHERE (released_at IS NULL AND status IN ('requested', 'checked_in', 'in_progress'))
);

CREATE INDEX appointment_resource_reservations_appointment_id_idx
  ON appointment_scheduler.appointment_resource_reservations (appointment_id, assigned_at);

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

CREATE OR REPLACE FUNCTION appointment_scheduler.enforce_technician_row_integrity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
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
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION appointment_scheduler.enforce_user_role_integrity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM appointment_scheduler.technicians
    WHERE user_id = NEW.user_id AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'technician users cannot have roles';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION appointment_scheduler.enforce_user_login_integrity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.auth_user_id <> '00000000-0000-0000-0000-000000000000'
     AND EXISTS (
       SELECT 1 FROM appointment_scheduler.technicians
       WHERE user_id = NEW.user_id AND deleted_at IS NULL
     ) THEN
    RAISE EXCEPTION 'technician users cannot have a login identity';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER technicians_enforce_user_integrity
  BEFORE INSERT OR UPDATE OF user_id ON appointment_scheduler.technicians
  FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.enforce_technician_row_integrity();
CREATE TRIGGER user_roles_enforce_technician_integrity
  BEFORE INSERT OR UPDATE OF user_id ON appointment_scheduler.user_roles
  FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.enforce_user_role_integrity();
CREATE TRIGGER users_enforce_technician_integrity
  BEFORE UPDATE OF auth_user_id ON appointment_scheduler.users
  FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.enforce_user_login_integrity();

CREATE OR REPLACE FUNCTION appointment_scheduler.reject_appointment_during_time_off()
RETURNS trigger LANGUAGE plpgsql AS $$
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

CREATE OR REPLACE FUNCTION appointment_scheduler.prevent_appointment_audit_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'appointment audit events are append-only';
END;
$$;

CREATE TRIGGER appointment_audit_events_append_only
  BEFORE UPDATE OR DELETE ON appointment_scheduler.appointment_audit_events
  FOR EACH ROW EXECUTE FUNCTION appointment_scheduler.prevent_appointment_audit_mutation();
