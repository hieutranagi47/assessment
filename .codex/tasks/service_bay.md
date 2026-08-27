Implement dealership-scoped Service Bay CRUD in the appointment_scheduler module, following the Go layout and conventions of /Users/hieutran/Development/go-ddd-skeleton/services/ht47agent.

Use OpenAPI-first APIs with oapi-codegen, PostgreSQL migrations, sqlc, Go pragmatic DDD, and focused tests.

Use the existing `service_bays` table:
- service_bay_id UUID primary key
- dealership_id UUID
- code
- name
- is_active
- created_at
- updated_at

Add a case-insensitive unique constraint/index on `(dealership_id, code)`. Codes and names are required; trim whitespace before validation. Do not physically delete a bay if it is assigned to any appointment. Return 409 and require setting is_active=false instead.

Expose:
- POST   /v1/dealerships/{dealershipId}/service-bays
- GET    /v1/dealerships/{dealershipId}/service-bays
- GET    /v1/dealerships/{dealershipId}/service-bays/{serviceBayId}
- PATCH  /v1/dealerships/{dealershipId}/service-bays/{serviceBayId}
- DELETE /v1/dealerships/{dealershipId}/service-bays/{serviceBayId}

List should support sensible pagination and optional `is_active` filtering. Responses include all resource fields and timestamps.

Authorization: only active authenticated dealership `admin` users can access these endpoints. Enforce path-dealership ownership for each bay and return scoped 404s for a bay outside the dealership.

Use consistent RFC 9457-style errors. Deliver migrations, sqlc queries, OpenAPI schemas/generated bindings, application and repository implementation, route wiring, and tests for admin-only access, ownership isolation, validation, uniqueness, and delete conflict behavior.