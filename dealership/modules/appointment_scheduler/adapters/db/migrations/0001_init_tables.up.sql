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
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT dealership_operation_time_day_check CHECK (day_of_week BETWEEN 1 AND 7),
  CONSTRAINT dealership_operation_time_hours_check CHECK (closes_at > opens_at),
  CONSTRAINT dealership_operation_time_day_unique UNIQUE (dealership_id, day_of_week)
);

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
   'Creates customers and vehicles; searches availability; creates and manages appointments.');

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
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX customers_email_unique_when_present
  ON appointment_scheduler.customers (lower(email))
  WHERE email IS NOT NULL;

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

CREATE TABLE appointment_scheduler.service_type_required_skills (
  service_type_required_skill_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_type_id UUID NOT NULL REFERENCES appointment_scheduler.service_types(service_type_id) ON DELETE CASCADE,
  skill_code VARCHAR(100) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  CONSTRAINT service_type_required_skills_unique UNIQUE (service_type_id, skill_code)
);

CREATE TABLE appointment_scheduler.service_type_required_bay_capabilities (
  service_type_required_bay_capability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_type_id UUID NOT NULL REFERENCES appointment_scheduler.service_types(service_type_id) ON DELETE CASCADE,
  capability_code VARCHAR(100) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  CONSTRAINT service_type_required_bay_capabilities_unique UNIQUE (service_type_id, capability_code)
);

CREATE TABLE appointment_scheduler.service_bays (
  service_bay_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dealership_id UUID NOT NULL REFERENCES appointment_scheduler.dealerships(dealership_id),
  code VARCHAR(50) NOT NULL,
  name VARCHAR(255) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT service_bays_dealership_code_unique UNIQUE (dealership_id, code)
);

CREATE TABLE appointment_scheduler.service_bay_capabilities (
  service_bay_capability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_bay_id UUID NOT NULL REFERENCES appointment_scheduler.service_bays(service_bay_id) ON DELETE CASCADE,
  capability_code VARCHAR(100) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  CONSTRAINT service_bay_capabilities_unique UNIQUE (service_bay_id, capability_code)
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
  skill_code VARCHAR(100) NOT NULL,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  CONSTRAINT technician_skills_unique UNIQUE (technician_id, skill_code)
);

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
  CONSTRAINT technician_shifts_hours_check CHECK (ends_at > starts_at)
);

CREATE TABLE appointment_scheduler.technician_time_off (
  technician_time_off_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  technician_id UUID NOT NULL REFERENCES appointment_scheduler.technicians(technician_id) ON DELETE CASCADE,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  CONSTRAINT technician_time_off_range_check CHECK (ends_at > starts_at)
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
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  CONSTRAINT appointments_time_range_check CHECK (ends_at > starts_at),
  CONSTRAINT appointments_status_check CHECK (
    status IN ('requested', 'checked_in', 'in_progress', 'completed', 'cancelled')
  ),
  CONSTRAINT appointments_cancel_reason_check CHECK (
    status <> 'cancelled' OR cancellation_reason IS NOT NULL
  )
);

CREATE INDEX appointments_dealership_starts_at_idx
  ON appointment_scheduler.appointments (dealership_id, starts_at);

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
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ
);

CREATE TABLE appointment_scheduler.appointment_idempotency (
  idempotency_key VARCHAR(255) PRIMARY KEY,
  appointment_id UUID REFERENCES appointment_scheduler.appointments(appointment_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ
);
