---
name: golang-ddd-architecture
description: "Design and refactor Go service architecture for DDD-style systems. Use when a Go codebase needs explicit ports/app/domain/adapters boundaries, dependency rules, interface placement, composition-root dependency injection, separate transport and database models, or help deciding whether DDD, Clean Architecture, or CQRS are justified."
user-invocable: true
license: MIT
compatibility: Designed for Codex, Claude Code, Gemini CLI, Cursor, OpenCode, and similar AI coding agents working with Go services.
metadata:
  author: joeyave
  version: "0.3.0"
---

# Golang DDD Architecture

Use this skill to shape a Go service so it stays easy to change, test, and reason about as business logic grows.

## Code Readability Standard

Generate code for people to review and maintain, not only for the compiler.

- Keep one meaningful operation per line. Split long expressions, function
  calls, and struct literals at natural boundaries.
- Prefer named intermediate variables when they make data flow or an error
  path easier to follow. Avoid dense one-liners and deeply nested expressions.
- Keep related code together, use descriptive names, and make control flow
  obvious before extracting abstractions.
- Run `gofmt` on every changed Go file. After formatting, manually reflow code
  that remains difficult to scan. Do not fight idiomatic Go merely to enforce
  an arbitrary line length.
- When adding generated or scaffolded code, apply the same readability standard
  before presenting it.

## Start Here

- Check whether the service is complex enough to justify the pattern.
- Keep the design smaller for simple CRUD or authentication flows where read and write shapes are mostly identical and business rules are thin.
- Use the full workflow when handlers keep growing `if` trees, models are reused across boundaries, or dependencies are hard to mock or untangle.

## Workflow

1. Inventory entry points, use cases, and module consumers.
- Start from HTTP handlers, gRPC services, CLI commands, message consumers, scheduled jobs, and other modules that consume a capability.
- Rewrite the supported operations in business language before moving code around.

2. Draw the boundary map.
- `ports` are inbound transport and serialization only.
- `app` orchestrates use cases.
- `domain` owns business rules and invariants.
- `adapters` talk to databases, queues, external APIs, files, and other infrastructure.

3. Enforce dependency direction.
- `domain` depends on nothing outside itself.
- `app` may import `domain` but not concrete transport or adapter packages.
- `ports` and `adapters` may import inward layers.
- Fix import cycles by moving interfaces inward or by splitting responsibilities, not by flattening everything into one package.

4. Place interfaces next to the consumer.
- Define interfaces in the package that needs the behavior.
- Keep them narrow and use-case-oriented.
- Inject implementations from the composition root.
- For capabilities consumed by another module, publish the implementation from
  `<module>/api/module`, define its consumer interface in
  `<module>/api/module/client`, and register it through the shared module
  contracts registry. Do not make `app`, `domain`, adapter, or module-root
  symbols the cross-module API.

5. Separate models that change for different reasons.
- Do not reuse one struct for DB rows, API responses, Pub/Sub payloads, and domain state unless their change cadence is truly the same.
- Accept data duplication when it removes coupling. DRY is usually more valuable for behavior than for data.

6. Keep `main` boring.
- Use `main` as the composition root.
- Wire repositories, clients, handlers, and configuration there.
- Do not hide business logic, validation, or workflow branching there.

7. Leave the codebase more testable than you found it.
- Domain rules should be unit-testable without mocks.
- Application orchestration should be testable with tiny handwritten mocks.
- Adapter behavior should be covered with integration tests.

## Use These References

- Read [references/architecture-rules.md](references/architecture-rules.md) for layer rules, package layouts, and anti-patterns.
- Read [references/naming-and-models.md](references/naming-and-models.md) when naming, model boundaries, or shared-struct tradeoffs are the hard part.

## Deliverables

- a clear layer map or package plan,
- dependency direction that compiles without import-cycle hacks,
- constructors or wiring points in the composition root,
- explicit model boundaries,
- a short backlog of follow-up refactors if the system is too tangled for one pass.
