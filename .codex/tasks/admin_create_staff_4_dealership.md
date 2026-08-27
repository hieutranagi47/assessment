# Adding staff for dealership

Implement a “grant dealership staff access” API in:

/Users/hieutran/Development/Assessment/dealership

Follow the existing Go monolith / pragmatic DDD conventions and the patterns already used by appointment_scheduler’s dealership-admin endpoint. Keep the change OpenAPI-first, regenerate oapi-codegen output, add sqlc queries as needed, and run Go tests.

Goal:
Create an appointment_scheduler.users record for an existing auth account and grant exactly one appointment-scheduler role: `admin`, `dealer`, or `staff`.

Important distinction:
- This API does not create an auth account and must not change the auth module role.
- The target account must already exist in auth and be resolved through:
  `auth.GetUserInfoByEmail(ctx, email)`.
- The scheduler user is linked through `appointment_scheduler.users.auth_user_id`.
- Use the canonical email and full name returned by auth; do not trust a client-supplied name.
- The target auth account must be active.
- Create the scheduler user and its `appointment_scheduler.user_roles` record atomically in one PostgreSQL transaction.

API:
- Add `POST /dealership-users`
- Bearer authentication required.
- Request body:
  ```json
  {
    "dealershipId": "uuid",
    "email": "user@example.com",
    "role": "admin"
  }
  ```
- `role` is required and restricted to `admin`, `dealer`, `staff`.
- Return `201 Created` with:
  ```json
  {
    "userId": "uuid",
    "authUserId": "uuid",
    "dealershipId": "uuid",
    "name": "Auth User Full Name",
    "email": "user@example.com",
    "isActive": true,
    "role": "admin",
    "createdAt": "RFC3339 timestamp",
    "updatedAt": "RFC3339 timestamp"
  }
  ```

Authorization:
1. Resolve the caller using `GetUserInfo(ctx, actorID)` from:
   `/Users/hieutran/Development/Assessment/dealership/modules/auth/api/module/module.go`.
2. The caller must be active.
3. Permit if either:
   - auth role is `superadmin` or `admin`; or
   - caller is an active `appointment_scheduler.users` member with scheduler role `admin` for the request’s `dealershipId`.
4. A scheduler admin may grant only within their own dealership, including assigning `admin`.
5. Return a stable `403` error slug such as `dealership_user_create_forbidden` when unauthorized.

Validation and error behavior:
- Reject a nil/malformed dealership ID and blank/invalid email or unsupported scheduler role with `400`.
- Return `404 dealership_not_found` when the dealership does not exist or is inactive.
- Return `404 auth_user_not_found` if the email cannot be found in auth.
- Return `400 auth_user_inactive` if the target auth user is inactive.
- Enforce the existing one-scheduler-user-per-auth-user rule. Return `409 auth_user_already_assigned` if already linked.
- Resolve the role from the global `appointment_scheduler.roles` table; do not hard-code role IDs.
- Preserve the existing zero UUID behavior only for technicians. This endpoint creates login-capable scheduler users, so `auth_user_id` must be non-zero.
- Use the project’s standard `common.Error` response model and existing error conventions.

Architecture:
- Replace/generalize the existing `DealershipAdmin`-specific application and repository flow as appropriate so it supports all three scheduler roles cleanly.
- Prefer names such as `CreateDealershipUser`, `DealershipUser`, and `CreateDealershipUserInput`.
- Keep authorization in the application layer and SQL persistence in the adapter.
- Add a narrowly scoped repository authorization method that verifies active scheduler-admin membership for a specific dealership; do not authorize a dealership admin globally.
- Do not add dealership_id to user_roles, because dealership ownership is defined by users.dealership_id.
- Do not modify unrelated auth APIs or schema.

Database/sqlc:
- Add/update SQL queries for:
  - finding an active dealership;
  - checking whether an auth user is already assigned;
  - getting a role by code;
  - checking whether an auth user is an active scheduler admin for a specific dealership;
  - inserting users + user_roles in one transaction.
- Respect UUID primary-key naming and existing migrations/schema conventions.
- Regenerate sqlc output.

Tests:
- application tests for superadmin, auth-admin, same-dealership scheduler-admin, wrong-dealership scheduler-admin, inactive caller, inactive target, unsupported role, and duplicate assignment;
- repository test or focused integration coverage that confirms user and role assignment are atomic;
- HTTP handler tests for 201, 400, 403, 404, and 409;
- ensure existing dealership-admin/search endpoints stay correct, adapting them only where necessary.

Before finishing, run `gofmt`, code generation, and the relevant Go test suite. Report changed files and test results.
```

This deliberately treats “create staff” as granting scheduler membership to an existing auth user—the model already separates auth identity from dealership-specific roles.