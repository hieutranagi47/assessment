All tables use UUID primary keys and singular table-stem `_id` columns (for example, `dealerships.dealership_id`). `users` represents dealership staff; customers remain separate because callers do not need authenticated accounts in this API-first scope.

## Core tables

### `dealerships`

| Column | Type | Rules |
|---|---|---|
| `dealership_id` | `uuid` | PK |
| `name` | `varchar(255)` | required |
| `code` | `varchar(50)` | required, unique |
| `address` | `text` | required |
| `timezone` | `varchar(64)` | required; IANA timezone, e.g. `Asia/Ho_Chi_Minh` |
| `is_active` | `boolean` | required, default `true` |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

### `dealership_operation_time`

| Column | Type | Rules |
|---|---|---|
| `dealership_operation_time_id` | `uuid` | PK |
| `dealership_id` | `uuid` | required, FK → `dealerships` |
| `day_of_week` | `smallint` | required; ISO values `1` Monday through `7` Sunday |
| `opens_at` | `time` | required; dealership-local time |
| `closes_at` | `time` | required; must be later than `opens_at` |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

Constraints:

- `UNIQUE (dealership_id, day_of_week)`
- `CHECK (day_of_week BETWEEN 1 AND 7)`
- `CHECK (closes_at > opens_at)`

### `users`

| Column | Type | Rules |
|---|---|---|
| `user_id` | `uuid` | PK |
| `auth_user_id` | `uuid` | required, default zero UUID: `00000000-0000-0000-0000-000000000000` |
| `name` | `varchar(255)` | required |
| `phone` | `varchar(50)` | nullable |
| `email` | `varchar(255)` | nullable |
| `dealership_id` | `uuid` | required, FK → `dealerships` |
| `is_active` | `boolean` | required, default `true` |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

Constraint:

```sql
CREATE UNIQUE INDEX users_auth_user_id_unique_when_present
ON users (auth_user_id)
WHERE auth_user_id <> '00000000-0000-0000-0000-000000000000';
```

This permits multiple staff rows without an auth identity while ensuring every real `auth_user_id` is unique.

### `roles`

| Column | Type | Rules |
|---|---|---|
| `role_id` | `uuid` | PK |
| `code` | `varchar(64)` | required, unique |
| `name` | `varchar(100)` | required |
| `description` | `text` | nullable |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

Create these fixed system records in the initial migration:

| `code` | Responsibility |
|---|---|
| `admin` | Full dealership configuration; creates users/technicians; manages all resources and schedules. |
| `staff` | Manages technician shifts, time off, and permitted technician details. |
| `dealer` | Creates customers and vehicles; searches availability; creates and manages appointments. |

### `user_roles`

| Column | Type | Rules |
|---|---|---|
| `user_role_id` | `uuid` | PK |
| `user_id` | `uuid` | required, FK → `users` |
| `role_id` | `uuid` | required, FK → `roles` |
| `created_at` | `timestamptz` | required |

Constraint:

```sql
UNIQUE (user_id, role_id)
```

## Customer and vehicle tables

### `customers`

| Column | Type | Rules |
|---|---|---|
| `customer_id` | `uuid` | PK |
| `name` | `varchar(255)` | required |
| `phone` | `varchar(50)` | required, unique when reliable as a business identifier |
| `email` | `varchar(255)` | nullable, unique when present |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

For nullable email, use a partial unique index:

```sql
CREATE UNIQUE INDEX customers_email_unique_when_present
ON customers (lower(email))
WHERE email IS NOT NULL;
```

Normalize phone numbers—preferably to E.164—before inserting. Enforce `UNIQUE (phone)` only when phone numbers are reliable business identifiers; otherwise use a non-unique index.

### `vehicles`

| Column | Type | Rules |
|---|---|---|
| `vehicle_id` | `uuid` | PK |
| `customer_id` | `uuid` | required, FK → `customers` |
| `vin` | `varchar(17)` | nullable, unique when present |
| `registration_plate` | `varchar(32)` | nullable |
| `make` | `varchar(100)` | required |
| `model` | `varchar(100)` | required |
| `model_year` | `smallint` | nullable |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

Constraint: enforce that at least one of `vin` or `registration_plate` is present.

## Service configuration tables

### `service_types`

| Column | Type | Rules |
|---|---|---|
| `service_type_id` | `uuid` | PK |
| `name` | `varchar(255)` | required |
| `default_duration_minutes` | `integer` | required, positive |
| `min_duration_minutes` | `integer` | required, positive |
| `max_duration_minutes` | `integer` | required, ≥ minimum |
| `is_active` | `boolean` | required, default `true` |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

### `service_type_required_skills`

| Column | Type | Rules |
|---|---|---|
| `service_type_required_skill_id` | `uuid` | PK |
| `service_type_id` | `uuid` | required, FK → `service_types` |
| `skill_code` | `varchar(100)` | required |
| `created_at` | `timestamptz` | required |

Constraint: `UNIQUE (service_type_id, skill_code)`.

### `service_type_required_bay_capabilities`

| Column | Type | Rules |
|---|---|---|
| `service_type_required_bay_capability_id` | `uuid` | PK |
| `service_type_id` | `uuid` | required, FK → `service_types` |
| `capability_code` | `varchar(100)` | required |
| `created_at` | `timestamptz` | required |

Constraint: `UNIQUE (service_type_id, capability_code)`.

## Resource tables

### `service_bays`

| Column | Type | Rules |
|---|---|---|
| `service_bay_id` | `uuid` | PK |
| `dealership_id` | `uuid` | required, FK → `dealerships` |
| `code` | `varchar(50)` | required |
| `name` | `varchar(255)` | required |
| `is_active` | `boolean` | required, default `true` |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

Constraint: `UNIQUE (dealership_id, code)`.

### `service_bay_capabilities`

| Column | Type | Rules |
|---|---|---|
| `service_bay_capability_id` | `uuid` | PK |
| `service_bay_id` | `uuid` | required, FK → `service_bays` |
| `capability_code` | `varchar(100)` | required |
| `created_at` | `timestamptz` | required |

Constraint: `UNIQUE (service_bay_id, capability_code)`.

### `technicians`

A technician is a staff member with technical qualifications. Their name and contact information belong to `users`.

| Column | Type | Rules |
|---|---|---|
| `technician_id` | `uuid` | PK |
| `user_id` | `uuid` | required, unique, FK → `users` |
| `is_active` | `boolean` | required, default `true` |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

The technician’s dealership is derived through `technicians.user_id → users.dealership_id`; do not duplicate it in `technicians`.

### `technician_skills`

| Column | Type | Rules |
|---|---|---|
| `technician_skill_id` | `uuid` | PK |
| `technician_id` | `uuid` | required, FK → `technicians` |
| `skill_code` | `varchar(100)` | required |
| `expires_at` | `timestamptz` | nullable |
| `created_at` | `timestamptz` | required |

Constraint: `UNIQUE (technician_id, skill_code)`.

### `technician_shifts`

| Column | Type | Rules |
|---|---|---|
| `technician_shift_id` | `uuid` | PK |
| `technician_id` | `uuid` | required, FK → `technicians` |
| `day_of_week` | `smallint` | required; `1` Monday–`7` Sunday |
| `starts_at` | `time` | required |
| `ends_at` | `time` | required |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |

A technician may have multiple shifts on the same day, such as morning and afternoon shifts.

### `technician_time_off`

| Column | Type | Rules |
|---|---|---|
| `technician_time_off_id` | `uuid` | PK |
| `technician_id` | `uuid` | required, FK → `technicians` |
| `starts_at` | `timestamptz` | required |
| `ends_at` | `timestamptz` | required |
| `reason` | `text` | nullable |
| `created_at` | `timestamptz` | required |

Constraint: `CHECK (ends_at > starts_at)`.

## Appointment tables

### `appointments`

| Column | Type | Rules |
|---|---|---|
| `appointment_id` | `uuid` | PK |
| `reference_code` | `varchar(50)` | required, unique |
| `customer_id` | `uuid` | required, FK → `customers` |
| `vehicle_id` | `uuid` | required, FK → `vehicles` |
| `dealership_id` | `uuid` | required, FK → `dealerships` |
| `service_type_id` | `uuid` | required, FK → `service_types` |
| `technician_id` | `uuid` | required, FK → `technicians` |
| `service_bay_id` | `uuid` | required, FK → `service_bays` |
| `starts_at` | `timestamptz` | required |
| `ends_at` | `timestamptz` | required |
| `status` | `varchar(32)` | required |
| `notes` | `text` | nullable |
| `created_by_user_id` | `uuid` | required, FK → `users` |
| `cancelled_by_user_id` | `uuid` | nullable, FK → `users` |
| `cancellation_reason` | `text` | nullable |
| `created_at` | `timestamptz` | required |
| `updated_at` | `timestamptz` | required |
| `cancelled_at` | `timestamptz` | nullable |
| `checked_in_at` | `timestamptz` | nullable |
| `started_at` | `timestamptz` | nullable |
| `completed_at` | `timestamptz` | nullable |

Allowed `status` values:

```text
requested
checked_in
in_progress
completed
cancelled
```

Key constraints:

- `CHECK (ends_at > starts_at)`
- `CHECK (status IN (...))`
- `CHECK (status <> 'cancelled' OR cancellation_reason IS NOT NULL)`
- `vehicle_id` must belong to `customer_id` — validate in the booking transaction.
- Technician and service bay must belong to the same dealership as the appointment — validate in the booking transaction.

### `appointment_audit_events`

| Column | Type | Rules |
|---|---|---|
| `appointment_audit_event_id` | `uuid` | PK |
| `appointment_id` | `uuid` | required, FK → `appointments` |
| `actor_user_id` | `uuid` | nullable, FK → `users` |
| `event_type` | `varchar(64)` | required |
| `before_data` | `jsonb` | nullable |
| `after_data` | `jsonb` | nullable |
| `occurred_at` | `timestamptz` | required |

## Required scheduling constraints

Use PostgreSQL exclusion constraints so concurrent requests cannot double-book a technician or bay:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE appointments
ADD CONSTRAINT appointments_no_technician_overlap
EXCLUDE USING gist (
  technician_id WITH =,
  tstzrange(starts_at, ends_at, '[)') WITH &&
)
WHERE (status IN ('requested', 'checked_in', 'in_progress'));

ALTER TABLE appointments
ADD CONSTRAINT appointments_no_service_bay_overlap
EXCLUDE USING gist (
  service_bay_id WITH =,
  tstzrange(starts_at, ends_at, '[)') WITH &&
)
WHERE (status IN ('requested', 'checked_in', 'in_progress'));
```

`[)` means an appointment ending at `10:00` does not conflict with another starting at `10:00`.
