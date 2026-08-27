Use this implementation prompt:

```text
Implement an API to create an Appointment Scheduler dealership admin.

Follow the existing Go monolith conventions and pragmatic DDD structure in:
- /Users/hieutran/Development/go-ddd-skeleton/services/ht47agent
- /Users/hieutran/Development/Assessment/dealership/modules/appointment_scheduler
- /Users/hieutran/Development/Assessment/dealership/modules/auth/api/module/module.go

Add:

POST /dealership-users/admins

Authorization:
- Require a valid Bearer token.
- Resolve the caller through auth.AuthenticateAccessToken, then auth.GetUserInfo(ctx, callerAuthUserID).
- Only an auth user with `status == "active"` and role `superadmin` or `admin` may create a dealership admin.
- Return 401 for missing/invalid authentication and 403 with slug `dealership_admin_create_forbidden` when the caller is not permitted.
- Do not trust role or identity fields from the request body.

Request body:
```json
{
  "authUserId": "UUID from auth.users.user_id",
  "dealershipId": "UUID",
  "name": "Jane Doe",
  "phone": "+84901234567",
  "email": "jane@example.com"
}
```

Rules:
- email is required in request body to search the user in the auth.users
- `authUserId` identifies an existing active user in `auth.users`; confirm this through the exported `GetUserInfo` module contract. Do not access auth persistence directly.
- `authUserId` must be non-zero.
- The target auth user may be assigned to only one non-deleted `appointment_scheduler.users` record. Return 409 `auth_user_already_assigned` if it is already assigned.
- `dealershipId` must refer to an active, non-deleted dealership. Return 404 `dealership_not_found` otherwise.
- Validate required `name`; normalize and validate `phone` as E.164 when supplied; trim and normalize `email` when supplied.
- Create an active `appointment_scheduler.users` record with a new UUID primary key, the supplied `auth_user_id`, profile data, and dealership ID.
- In the same PostgreSQL transaction, grant exactly the scheduler `admin` role by inserting `appointment_scheduler.user_roles` for the seeded global `roles.code = 'admin'`.
- Never create a technician record for this endpoint.
- The operation must be atomic: failure to create either the user or role assignment rolls back both.
- Handle concurrent requests safely. Translate the partial unique-index violation on `users.auth_user_id` to the conflict error above.
- Do not add `dealership_id` to `user_roles`; it belongs exclusively to `users`.

Response:
- Return 201 with the created user and assigned role:
```json
{
  "userId": "UUID",
  "authUserId": "UUID",
  "dealershipId": "UUID",
  "name": "Jane Doe",
  "phone": "+84901234567",
  "email": "jane@example.com",
  "isActive": true,
  "role": "admin",
  "createdAt": "RFC3339 timestamp",
  "updatedAt": "RFC3339 timestamp"
}
```

Implementation requirements:
- Update the appointment scheduler OpenAPI spec first, then regenerate code with oapi-codegen. Do not hand-edit generated files.
- Add focused application/domain logic, keeping HTTP handlers thin.
- Add sqlc queries for: active dealership lookup, scheduler-user lookup by auth_user_id, role lookup by code, and transactional user-plus-role creation. Regenerate sqlc output; do not hand-edit generated files.
- Preserve the project’s structured `ErrorResponse` convention.
- Add tests covering: superadmin success, auth-admin success, unauthorized caller, inactive/unauthorized caller, missing target auth user, inactive target auth user, inactive/missing dealership, duplicate assignment, rollback on role-assignment failure, and response serialization.
- Run `gofmt` and the relevant Go test suite.
```

One design note: this treats auth `admin` as globally authorized, matching the existing `CreateDealership` authorization behavior.