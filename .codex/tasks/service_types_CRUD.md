Implement dealership-scoped Service Type CRUD in the appointment_scheduler module, following the conventions in /Users/hieutran/Development/go-ddd-skeleton/services/ht47agent.

Use Go, pragmatic DDD, OpenAPI-first contracts generated with oapi-codegen, PostgreSQL migrations, and sqlc. Do not introduce CQRS beyond what is useful for straightforward CRUD.

Add `dealership_id UUID NOT NULL REFERENCES dealerships(dealership_id)` to `service_types` so service types are owned by a dealership. Preserve UUID primary keys and created_at/updated_at conventions.

Expose these endpoints:
- POST   /v1/dealerships/{dealershipId}/service-types
- GET    /v1/dealerships/{dealershipId}/service-types
- GET    /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}
- PATCH  /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}
- DELETE /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}

Service type fields: service_type_id, dealership_id, name, default_duration_minutes, min_duration_minutes, max_duration_minutes, is_active, created_at, updated_at.

Validate positive durations and `min_duration_minutes <= default_duration_minutes <= max_duration_minutes`. Names must be unique per dealership, case-insensitively.

Authorization: only an authenticated active user with the `admin` role for the path dealership may access every endpoint. Never trust dealershipId from the body; use the authenticated user’s dealership membership and the path ID. Return 403 for a valid user outside the dealership or without admin role.

Delete behavior: reject deletion with 409 if the service type is referenced by any appointment; admins can set is_active=false instead. Return consistent RFC 9457-style problem responses for validation, unauthorized, forbidden, not found, conflict, and internal errors.

Add migrations, sqlc queries, OpenAPI schemas, generated code, HTTP handlers, application/service layer, repository code, and focused tests for authorization, validation, uniqueness, and deletion conflicts. Run formatting and relevant tests.