Implement CRUD for required bay capabilities of a dealership service type in the appointment_scheduler module, aligned with /Users/hieutran/Development/go-ddd-skeleton/services/ht47agent.

Use Go, OpenAPI-first/oapi-codegen, PostgreSQL migrations, sqlc, and pragmatic DDD. The parent service type must be dealership-scoped.

Assume a capabilities catalog exists or create the minimal normalized `bay_capabilities` table if absent. Create `service_type_required_bay_capabilities` with:
- service_type_required_bay_capability_id UUID primary key
- service_type_id UUID not null
- bay_capability_id UUID not null
- created_at and updated_at
- unique(service_type_id, bay_capability_id)

Expose:
- POST   /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}/required-bay-capabilities
- GET    /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}/required-bay-capabilities
- PATCH  /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}/required-bay-capabilities/{requiredCapabilityId}
- DELETE /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}/required-bay-capabilities/{requiredCapabilityId}

POST accepts bay_capability_id. PATCH may replace it, while preserving uniqueness. Include resource IDs and timestamps in responses.

Authorization: every endpoint is restricted to active users who hold the `admin` role at dealershipId. Validate that the parent service type belongs to dealershipId and each nested resource belongs to the indicated parent. Do not allow cross-dealership linkage.

Use RFC 9457-style problem errors, including 400 validation, 401 unauthenticated, 403 non-admin, 404 scoped resource not found, and 409 duplicate association. Add migrations, sqlc queries, OpenAPI contracts/generated code, implementation layers, and focused authorization and integrity tests.