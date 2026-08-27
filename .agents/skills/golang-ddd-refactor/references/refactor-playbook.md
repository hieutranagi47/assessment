# Refactor Playbook

## Before You Move Code

- Start from one painful use case, not the whole service.
- Prefer an endpoint or command with visible business rules over a data-only read.
- Write down who can do what, when, and under which constraints.

## Migration Steps

1. Identify the behavior hidden inside a handler, service, or repository transaction.
2. Name the operation in business language.
3. Create or refine a domain type that owns the rule.
4. Move validation and state transitions into behavior methods.
5. Add or tighten constructors so invalid instances are rejected.
6. Introduce persistence mapping if the old model leaks storage concerns.
7. Replace repository business methods with load or update capabilities.
8. Add domain tests before deleting the old validation code.
9. Collapse the old handler or service into orchestration only.

## Repository Pattern Guidance

- Put repository interfaces in the package that needs them.
- Keep repository names generic enough to survive domain changes.
- Prefer methods like `Get`, `GetOrCreate`, `Update`, `Save`.
- Use `Update(ctx, id, fn)` when the repository should own the transaction and the domain should own the decision.

## Anti-Pattern Checklist

- one shared model for API, DB, and domain,
- setters and public fields controlling core state,
- repository methods mirroring every business action,
- authorization checks mixed with transport parsing,
- domain packages importing persistence or transport libraries,
- business logic tested only through slow integration tests.

## Example Direction In This Style

- `UpdateHour` with many transport-level flags becomes domain behavior like `ScheduleTraining` or `CancelTraining`.
- Reschedule approval logic moves from an application service callback into `Training.ApproveReschedule`.
- Transactional persistence stays in the repository, while the business decision lives in the closure and domain type.
