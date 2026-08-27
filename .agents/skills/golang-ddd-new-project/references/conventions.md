# Generated service conventions

The generated project copies `services/auth/common`, the tested reference
implementation for Echo configuration, correlation-aware logging, public error
responses, UUID values, and module lifecycle interfaces.

```
cmd/main.go          process composition and shutdown
service.go           initializes modules, contracts, and HTTP routes
common/              cross-cutting infrastructure only
<module>/domain/     entities, value objects, and invariants
<module>/app/        use-case orchestration and consumer-owned interfaces
<module>/adapters/   SQL, queues, and third-party implementations
<module>/api/http/   request/response mapping and route registration
<module>/module.go   module lifecycle wiring
```

Dependencies point inward: `domain` imports no adapters or transport; `app`
may import `domain`; `api` and `adapters` may import inward layers. New modules
must be passed explicitly from `cmd/main.go` to `service.New`.

The scaffold's `/health` route only proves composition. Replace the generated
`/<module>/health` route with an actual bounded-context API and add tests at
the layer that owns the behavior.

## HTTP error contract

Every module exposes one consistent client error shape, whether it is backed by
commands or queries:

```json
{"message":"client-safe message","slug":"stable_slug","details":[]}
```

Use `common.Error` in application code for known client-safe errors and map it
at the HTTP port to the generated OpenAPI error model. Keep status selection in
the HTTP port, do not serialize Go errors or `InternalError`, and use a stable
fallback for unexpected errors. Define `ErrorResponse` and `ErrorDetail` in
each OpenAPI document with all fields required; regenerate code and test both
structured and fallback responses.
