# Application Tests And Errors

## What To Test In Handlers

- correct orchestration order,
- correct calls to repositories or outbound services,
- correct mapping of command inputs into domain calls,
- correct reaction to domain or adapter errors.

## What Not To Test There

- domain edge cases that are already covered in domain tests,
- private repository behavior,
- transport serialization details.

## Mocking Style

- Prefer tiny handwritten mocks over heavy mocking frameworks.
- If a handler needs too many stubbed methods, the interface is too wide.
- Separate handlers often make tests smaller immediately.

## Error Boundaries

- Keep app-layer errors transport-agnostic.
- Return `common.Error` when the use case can provide a client-safe status,
  slug, message, or field-level details. Do not return HTTP/OpenAPI types from
  commands or queries.
- Translate errors into HTTP codes or gRPC status at the port boundary.
- Every HTTP command/query failure must serialize as
  `{"message": string, "slug": string, "details": []}` using the generated
  OpenAPI error type. Map `common.Error.PublicError`, `ErrorSlug`, and
  `Details`; do not expose `InternalError` or use `err.Error()` as the body.
- Use stable slugs or typed errors when the same use case is exposed via
  multiple ports. For unknown errors, use a stable client-safe fallback and
  log the original error.

## HTTP Error Contract Tests

- Test that a `common.Error` retains its message, slug, and each detail record.
- Test that an unknown error becomes the safe fallback rather than leaking its
  text.
- Test the serialized body has `message`, `slug`, and `details`, including an
  empty `details` array.

## POST And Created Resources

If a command creates an entity and the client wants it back:

- prefer `204 No Content` with `content-location` when practical, or
- run an explicit query after the command succeeds.

Providing the entity UUID inside the command keeps this workable even if command execution later becomes asynchronous.
