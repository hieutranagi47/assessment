Implement an API-first Dealership module in this Go monolith.

Scope: create the dealership API only. Do not implement appointments, customers, technicians, bays, or scheduling yet.

Repository conventions:
- Follow the structure of the project
- Use pragmatic DDD boundaries: domain, app, API adapters, DB adapter, and module composition root.
- Keep the auth module decoupled. Obtain authorization-relevant user data exclusively through:
  /Users/hieutran/Development/Assessment/dealership/modules/auth/api/module/module.go
  specifically `GetUserInfo(ctx, userID)`.
- The returned auth user info includes `UserID`, `FullName`, `Status`, and `Role`.
- Valid privileged roles are exactly `superadmin` and `admin`.

Authorization:
- `POST /dealerships` may be called only by an authenticated active user whose role is `superadmin` or `admin`.
- All other roles, inactive users, unauthenticated users, and missing auth users must be rejected.
- Return 401 for missing/invalid authentication and 403 for authenticated but unauthorized callers.
- Enforce authorization in the application layer, not only the HTTP handler.
- Do not import auth domain or persistence packages from the dealership module; depend only on its public module client/interface.

API:
- Create an OpenAPI specification as the source of truth and generate HTTP types/interfaces using `oapi-codegen`.
- Add `POST /dealerships`.
- Request body:
  - `name`: required, non-empty
  - `code`: required, non-empty; normalize consistently (trim and uppercase)
  - `address`: required, non-empty
  - `timezone`: required IANA timezone, such as `Asia/Ho_Chi_Minh`
- Successful response: `201 Created`, returning:
  - `dealershipId` UUID
  - `name`
  - `code`
  - `address`
  - `timezone`
  - `isActive`
  - `createdAt`
  - `updatedAt`
- Use a consistent JSON error envelope, including stable machine-readable error codes for validation, conflict, unauthenticated, and forbidden errors.
- Return 409 when dealership code already exists.

Persistence:
- Add PostgreSQL migration(s) for `dealerships`:
  - `dealership_id UUID` primary key
  - `name`
  - `code`, unique
  - `address`
  - `timezone`
  - `is_active`, default true
  - `created_at`
  - `updated_at`
- Use UUIDs for IDs and UTC `timestamptz` timestamps.
- Validate timezones in Go using the IANA location database before persistence.
- Add sqlc queries and generate/update the DB query package.
- Use transactions only where needed; creation itself should be atomic.

Domain/application behavior:
- Create a dealership aggregate/entity with invariant validation.
- Do not expose database models directly through HTTP.
- Inject clock and UUID generation where this matches existing repository conventions.
- Add focused tests for:
  - superadmin can create a dealership
  - admin can create a dealership
  - ordinary user is forbidden
  - inactive privileged user is forbidden
  - invalid timezone is rejected
  - duplicate code returns conflict
  - HTTP handler maps auth/domain errors to the required status codes

Verification:
- Run `gofmt`, generated-code commands, relevant Go tests, and the full test suite if practical.
- Preserve unrelated worktree changes.
- At completion, summarize changed files, API behavior, authorization enforcement point, and test results.