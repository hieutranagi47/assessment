# Architecture Rules

## Layer Matrix

| Layer | Purpose | Can import | Must not import |
| --- | --- | --- | --- |
| `domain` | business rules, invariants, behavior | standard library, local domain packages | transport, protobuf, SQL, Firestore, HTTP clients, Terraform, Cloud SDKs |
| `app` | orchestration and use cases | `domain`, consumer-owned interfaces | concrete adapters, HTTP handlers, gRPC servers |
| `ports` | inbound transport | `app`, `domain` DTO mapping helpers | concrete adapter internals |
| `adapters` | outbound integrations | `app`, `domain` | inbound transport packages |
| `api/module` | public in-process capability for other modules | `app`, `domain`, narrow module API dependencies | HTTP transport, concrete adapter internals |
| `api/module/client` | consumer interface for a module capability | standard library and shared API types | provider implementation packages |

## Go-Specific Rules

- Define interfaces where they are consumed, not where they are implemented.
- Keep interfaces small enough that handwritten mocks stay trivial.
- Use `main` or a dedicated wiring package as the composition root.
- Treat import cycles as a design signal. Move the interface inward or split the use case instead of collapsing packages.
- Publish every cross-module capability from `<module>/api/module`, not from a
  module root, `app`, `domain`, or adapter package. Put the matching consumer
  interface in `<module>/api/module/client`, register the implementation in
  `common/module/contracts.Contracts`, and inject that interface into consumers.

## Model Boundaries

- Separate DB models from HTTP or gRPC response models when they change for different reasons.
- Separate domain types from persistence models when storage concerns start shaping the behavior model.
- Duplicate data shapes if it removes coupling between layers.
- Prefer mapping code over one shared struct with many tags and special-case mutations.

## Package Layouts That Fit This Style

Small service:

```text
internal/trainings/
  ports/http/
  app/
  domain/training/
  adapters/
```

Service with pragmatic CQRS:

```text
internal/trainings/
  ports/http/
  ports/grpc/
  app/command/
  app/query/
  domain/training/
  adapters/
```

## Anti-Patterns

- HTTP or gRPC handlers directly mixing database reads, authorization, and business rules.
- One `service` type with many unrelated methods and a wide dependency interface.
- Reusing the same struct for Firestore, JSON responses, and domain behavior.
- Domain packages importing protobuf, SQL drivers, Firestore clients, or HTTP clients.
- Moving everything into one package just to avoid import cycles.
- Treating microservices as the fix for bad boundaries inside a service.

## Keep The Design Smaller When

- The service is simple CRUD over one data shape.
- The business language is not richer than create, update, delete, and list.
- Most complexity sits in infrastructure plumbing rather than domain behavior.
- A heavier split would only add ceremony without improving testability or change isolation.

## Example Project

- Practical example repo used across the book: [ThreeDotsLabs/wild-workouts-go-ddd-example](https://github.com/ThreeDotsLabs/wild-workouts-go-ddd-example)
