# Testing And Security

## Test Architecture

- Domain tests: fast, black-box, no mocks, high coverage of business rules.
- Application tests: mock collaborators, verify orchestration, keep business edge cases in domain tests unless orchestration itself is complex.
- Integration tests: verify adapters, transactions, repository behavior, and real database usage.
- Component tests: exercise one service end to end with mocked external services.
- End-to-end tests: keep only for critical paths and contract double-checks.

## Stability Rules

- Run non-unit tests in parallel when possible.
- Avoid `sleep` for synchronization.
- Wait for explicit readiness or use eventual assertions with a timeout.
- Keep fixtures isolated so tests do not leak state across runs.

## Secure-By-Design Guidance

- Do not pass required auth data via `context.Context`.
- Do not invent fake users for internal operations.
- Prefer explicit roles or separate commands for privileged operations.
- If repository methods bypass normal actor checks, name them so the caller sees the risk immediately.

## Review Checklist

- Does any privileged path rely on hidden context values?
- Does any internal operation pretend to be a normal user?
- Are repository methods explicit about authorization assumptions?
- Are integration tests checking the repository and transaction contract rather than database trivia?
