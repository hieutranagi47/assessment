# Naming And Models

## Business Naming

- Prefer business verbs such as `ScheduleTraining`, `CancelTraining`, `ApproveReschedule`, `MoveTraining`.
- Avoid default CRUD verbs when the business does not speak that way.
- Use the same business noun across ports, app, and domain unless a boundary demands translation.
- Rename vague technical abstractions like `Manager`, `Processor`, `Util`, or `CommonService` into the use case or concept they actually represent.

## Model Separation Heuristics

- If a field should exist in storage but not on the public API, split the models.
- If a transport schema is optimized for clients while persistence is optimized for queries, split the models.
- If the domain needs private fields or invariants, split the domain model from DB and transport models.
- If one change request repeatedly asks for "add field here, but do not expose it there", the shared model is already the wrong abstraction.

## Good Friction

Some duplication is intentional:

- mapping DB model to application or domain type,
- mapping domain or query type to HTTP or gRPC response,
- separate command payloads and query responses,
- separate internal and external update paths when security rules differ.

## Error Shaping

- Keep application errors transport-agnostic.
- Return `common.Error` when application code knows a client-safe status, slug,
  message, or field details. Preserve its `Details`; retain diagnostic causes
  only in `InternalError`.
- Prefer stable sentinel or typed errors when an application error must be
  mapped differently by more than one transport.
- Translate errors at the port boundary, not in the app or domain layers. For
  HTTP, map to the generated OpenAPI model rather than serializing the Go error
  or returning `err.Error()`.
- Standardize every HTTP failure as `message`, `slug`, and `details` (an empty
  array when there are no details). Do not expose `HttpErrorCode` or
  `InternalError` in JSON.

## Review Checklist

- Can a non-technical stakeholder understand the important method names?
- Can a DB field change without forcing an API change?
- Can an API response change without forcing a DB migration?
- Can domain behavior evolve without changing protobuf or JSON types first?
- Does the current naming expose business concepts rather than implementation details?
