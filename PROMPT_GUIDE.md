```text
We are designing an API-first Appointment Scheduler for vehicle service dealerships.

Goal:
Replace manual booking. Dealership staff book appointments after customers call/message. A confirmed booking must reserve exactly one compatible service bay and one qualified technician for the entire service duration.

Tech stack:
- Go monolith with pragmatic DDD
- Follow conventions from /Users/hieutran/Development/go-ddd-skeleton/services/ht47agent
- OpenAPI-first APIs, generated with oapi-codegen
- PostgreSQL migrations and generated DB queries with sqlc

Scope decisions:
- Frontend is deferred.
- Only dealership staff can create customer records and appointments.
- Advisors can adjust appointment duration within the service type’s allowed range.
- One technician and one service bay per appointment.
- Deferred: payments, notifications, WhatsApp/SMS, parts/inventory, external dealer-system integrations, multi-resource services.
- Appointment statuses: requested, checked_in, in_progress, completed, cancelled.
- `requested` means the booking is accepted and resources are already reserved.

Core scheduling rules:
- Verify dealership operating hours, technician shifts/time-off, required technician skills, and required bay capabilities.
- Active statuses requested, checked_in, and in_progress block technician and bay capacity.
- completed and cancelled do not block capacity.
- Use PostgreSQL transactions plus exclusion constraints on technician/time-range and bay/time-range to prevent concurrent double booking.
- Store instants as timestamptz/UTC; use dealership IANA timezone for local operating-time validation.
- Interval uses [start, end), so an appointment ending at 10:00 does not conflict with one beginning at 10:00.

Database conventions:
- Every primary key is UUID.
- PK column naming uses singular table stem + `_id`, e.g. dealerships.dealership_id.
- Include created_at and updated_at on mutable tables.
- Core tables:
  - dealerships(dealership_id, name, code, address, timezone, is_active)
  - dealership_operation_time(dealership_operation_time_id, dealership_id, day_of_week [1=Mon…7=Sun], opens_at, closes_at)
  - users(user_id, auth_user_id, name, phone, email, dealership_id, is_active)
  - roles(role_id, code, name, description)
  - user_roles(user_role_id, user_id, role_id)
  - customers(customer_id, name, phone, email)
  - vehicles(vehicle_id, customer_id, vin, registration_plate, make, model, model_year)
  - service_types(service_type_id, name, default_duration_minutes, min_duration_minutes, max_duration_minutes, is_active)
  - service_type_required_skills
  - service_type_required_bay_capabilities
  - service_bays(service_bay_id, dealership_id, code, name, is_active)
  - service_bay_capabilities
  - technicians(technician_id, user_id, is_active)
  - technician_skills
  - technician_shifts
  - technician_time_off
  - appointments
  - appointment_audit_events

Identity and role model:
- users are dealership employees.
- auth_user_id defaults to zero UUID: 00000000-0000-0000-0000-000000000000.
- Non-zero auth_user_id values are unique via a partial unique index.
- Roles are global definitions, assigned through user_roles; do not duplicate dealership_id in user_roles because it is already on users.
- Seed roles:
  - admin: all dealership configuration, create users/technicians, manage all resources.
  - staff: manage permitted technician information, shifts, and time off.
  - dealer: create/find customers and vehicles; search availability; create/manage appointments.
- Technicians are users linked by technicians.user_id, with zero auth_user_id and no user_roles record; they cannot log in.
- Customer phone is required and unique. Email is nullable but case-insensitively unique when supplied. Normalize phone numbers to E.164 before storage.

Appointments contain:
appointment_id, reference_code, customer_id, vehicle_id, dealership_id, service_type_id, technician_id, service_bay_id, starts_at, ends_at, status, notes, created_by_user_id, cancellation metadata, lifecycle timestamps, created_at, updated_at.

Next discussion:
Define the API resource boundaries, endpoint set, OpenAPI request/response models, authorization matrix, error model, and exact lifecycle/reschedule/reassignment rules.
```
Give me a prompt to create some apis for the appointment_scheduler.appointments table:
Only admin/staff/dealer can create/update/delete it.
Check some conditions:
- Time zone with dealership operation time.
- Technician available time slot (technician time shifts & technician time off).
- Available service bay.
And check other related conditions, if you have any questions, ask me to discuss more before generating the final prompt in need