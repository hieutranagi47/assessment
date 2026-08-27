Implement CRUD for assigning capabilities to a dealership service bay in the appointment_scheduler module, following /Users/hieutran/Development/go-ddd-skeleton/services/ht47agent conventions.

Use Go pragmatic DDD, OpenAPI-first contracts generated through oapi-codegen, PostgreSQL migrations, sqlc, and focused tests.

Assume the global `bay_capabilities` catalog exists or create it if absent:
- bay_capability_id UUID primary key
- code unique, case-insensitive
- name
- description nullable
- created_at, updated_at

Use `service_bay_capabilities` as the association table:
- service_bay_capability_id UUID primary key
- service_bay_id UUID not null
- bay_capability_id UUID not null
- created_at, updated_at
- unique(service_bay_id, bay_capability_id)

Expose:
- POST   /v1/dealerships/{dealershipId}/service-bays/{serviceBayId}/capabilities
- GET    /v1/dealerships/{dealershipId}/service-bays/{serviceBayId}/capabilities
- PATCH  /v1/dealerships/{dealershipId}/service-bays/{serviceBayId}/capabilities/{serviceBayCapabilityId}
- DELETE /v1/dealerships/{dealershipId}/service-bays/{serviceBayId}/capabilities/{serviceBayCapabilityId}

POST accepts bay_capability_id. PATCH may replace the assigned capability and must enforce the unique association. List responses should include association IDs, timestamps, and capability code/name.

Authorization: only active users with the `admin` role for dealershipId may use these APIs. Verify that serviceBayId belongs to dealershipId and that the association belongs to that bay. A capability catalog item may be global, but its assignment must never cross dealership boundaries.

Use scoped 404 responses, 409 for duplicates, and RFC 9457-style problem details for all errors. Include migrations, sqlc queries, OpenAPI definitions/generated code, handler/application/repository implementation, and tests for authorization, ownership, duplicate assignment, and deletion.