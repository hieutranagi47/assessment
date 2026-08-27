---
name: golang-ddd
description: "Entry-point router for Go architecture and refactoring tasks focused on DDD-style services. Use when working on a Go service and you want one skill to decide whether the task is primarily about architecture boundaries, domain-first refactoring, pragmatic CQRS, or delivery and test support. This skill should select one or more companion skills and apply them in the right order."
user-invocable: true
license: MIT
compatibility: Designed for Codex, Claude Code, Gemini CLI, Cursor, OpenCode, and similar AI coding agents working with Go services.
metadata:
  author: joeyave
  version: "0.3.0"
---

# Golang DDD

Use this as the default manual entry point when the task is “make this Go service easier to evolve without over-engineering” but the exact technique is not yet obvious.

## Code Readability Standard

Apply this standard to every companion skill selected by the router.

- Generate code for human review and maintenance. Keep one meaningful operation
  per line and break long expressions, calls, literals, and conditions at
  natural boundaries.
- Prefer descriptive names, explicit intermediate steps, and linear control
  flow over dense one-liners or deeply nested expressions.
- Run the formatter appropriate to the language, including `gofmt` for Go, and
  manually reflow code that remains difficult to scan. Do not impose an
  arbitrary line limit when idiomatic formatting is clearer.
- Inspect generated and reformatted code before delivery. Readability is part
  of correctness because unclear code is harder to test and safely change.

## Routing Workflow

1. Start by classifying the task.
- If the main problem is package structure, layer boundaries, shared models, dependency direction, or import cycles, start with `$golang-ddd-architecture`.
- If the main problem is business rules hidden in handlers, repositories, or mutable structs, start with `$golang-ddd-refactor`.
- If the main problem is a wide application service, CRUD names, mixed reads and writes, or handler-specific dependency sprawl, start with `$golang-ddd-cqrs`.
- If the main problem is Terraform, CI, test strategy, service auth, or secure internal operations, start with `$golang-ddd-infrastructure`.

2. Combine skills when the task spans layers.
- Architecture + domain refactor is the most common pair for rescue refactors.
- Domain refactor + CQRS fits when write-side business logic already exists and the app layer is too wide.
- Architecture + infrastructure fits when CI or deployment work is exposing missing boundaries.
- Infrastructure may follow any of the others when tests, auth, or delivery constraints need to be aligned with the code structure.

3. Use this default order when multiple skills apply.
- First `$golang-ddd-architecture`
- Then `$golang-ddd-refactor`
- Then `$golang-ddd-cqrs`
- Finally `$golang-ddd-infrastructure`

4. Keep the solution proportional.
- Do not force CQRS into simple CRUD.
- Do not split models or layers more than the current complexity needs.
- Prefer the smallest change that makes the code safer to modify.

## Manual Invocation Tips

- Use `golang-ddd` when you are unsure which specialized skill is the right one.
- Use a specialized skill directly when the problem is already obvious.
- If the request asks for a domain-oriented cleanup or refactor without more detail, start here.

## Companion Skills

- `$golang-ddd-architecture`
- `$golang-ddd-refactor`
- `$golang-ddd-cqrs`
- `$golang-ddd-infrastructure`

## Deliverables

- a clear choice of which companion skill or skill sequence to use,
- a scoped plan that matches the actual complexity,
- avoidance of over-engineering for simple services.
