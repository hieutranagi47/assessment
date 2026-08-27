Implement CRUD for service type required skills in the appointment_scheduler module, following /Users/hieutran/Development/go-ddd-skeleton/services/ht47agent conventions.

Use Go pragmatic DDD, OpenAPI-first with oapi-codegen, PostgreSQL migrations, and sqlc. A required-skill record belongs to a dealership-owned service type. Ensure the parent service type is scoped to the path dealership.

Assume a skills catalog exists or create the minimal normalized `skills` table if it is absent. Create `service_type_required_skills` with UUID primary key `service_type_required_skill_id`, `service_type_id`, `skill_id`, created_at, updated_at, and a unique constraint on `(service_type_id, skill_id)`.

Expose:
- POST   /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}/required-skills
- GET    /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}/required-skills
- PATCH  /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}/required-skills/{requiredSkillId}
- DELETE /v1/dealerships/{dealershipId}/service-types/{serviceTypeId}/required-skills/{requiredSkillId}

Use request/response models that expose IDs, timestamps, and associated skill details where useful. Since this is a pure association, PATCH may only support changing the skill_id; it must reject a duplicate association with 409.

Authorization: only an active authenticated dealership `admin` for dealershipId can use these endpoints. Verify that serviceTypeId belongs to dealershipId and that requiredSkillId belongs to the specified service type. Return 404 for missing or cross-parent resources so IDs cannot be enumerated across dealership boundaries.

Use consistent RFC 9457-style errors. Add migrations, sqlc queries, OpenAPI definitions and generated code, handler/application/repository layers, and tests for parent ownership, admin-only access, duplicate prevention, and deletion.