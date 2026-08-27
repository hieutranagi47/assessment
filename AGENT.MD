# Dealership service guidance

## Project overview

This repository contains one standalone Go HTTP service named `dealership`.
The service is an appointment and authentication backend backed by PostgreSQL.
The Go module lives in `dealership/` and its module path is `assessment`.

There is no Go workspace file in the repository. Run Go commands from the
`dealership/` directory unless a command explicitly says otherwise.

## Runtime architecture

`dealership/cmd/main.go` is the composition root. It loads environment
configuration, creates the PostgreSQL connection pool, constructs the service,
initializes modules, and starts both HTTP and HTTPS listeners.

The root service in `dealership/service.go` owns the Echo router and module
lifecycle. It initializes the modules in this order:

1. `auth` — credentials, users, roles, password hashing, email encryption and
   lookup, JWT issuing/verification, and authentication HTTP endpoints.
2. `appointment_scheduler` — dealerships, customers, vehicles, service types,
   technicians, service bays, appointment availability, and appointment
   lifecycle operations.

Both bounded contexts share one PostgreSQL instance and connection pool, but
each owns a separate PostgreSQL schema and embedded migration set:

- `auth` schema: `modules/auth/adapters/db/migrations/`
- `appointment_scheduler` schema:
  `modules/appointment_scheduler/adapters/db/migrations/`

The common module contains cross-cutting infrastructure only: configuration,
Echo setup and middleware, logging, UUID helpers, error mapping, transaction
helpers, migration support, and module lifecycle contracts.

## Package boundaries

Each bounded context follows a domain-oriented structure:

```text
dealership/
├── cmd/
│   └── main.go                 # application composition root
├── service.go                  # service wiring and HTTP/TLS lifecycle
└── modules/
    ├── common/                 # shared infrastructure and lifecycle contracts
    ├── auth/
    │   ├── domain/             # User entity, statuses, and invariants
    │   ├── app/                # authentication use cases and consumer ports
    │   ├── adapters/db/        # PostgreSQL repository, SQL, sqlc models, migrations
    │   ├── adapters/token/     # JWT token adapter
    │   ├── api/http/            # OpenAPI source, generated server, HTTP handlers
    │   └── api/module/          # published in-process auth contract
    └── appointment_scheduler/
        ├── domain/             # Appointment entity and lifecycle invariants
        ├── app/                # scheduling use cases and repository port
        ├── adapters/db/        # PostgreSQL repository, SQL, sqlc models, migrations
        └── api/http/            # OpenAPI source, generated server, HTTP handlers
```

Dependency direction is inward: domain code is infrastructure-free; app code
orchestrates domain behavior through narrow interfaces; adapters implement
database and token concerns; HTTP packages translate requests and responses.
Database row models, generated API models, and domain entities are separate.

The scheduler consumes authentication through the published
`modules/auth/api/module/client` contract. Cross-module consumers must use
that contract rather than importing auth repositories, handlers, or concrete
application internals.

## HTTP surface

- `GET /health` returns HTTP 204 when the process is running.
- Auth API: `/auth/v1/...`
- Auth interactive docs: `/auth/docs/`
- Auth OpenAPI document: `/auth/docs/openapi.yaml`
- Appointment API: `/v1/appointments...`

All appointment operations require authentication. The auth handler owns token
authentication and the scheduler receives the small in-process identity
contract from the auth module.

The service creates a development self-signed TLS certificate in memory from
the configured RSA key pair. Do not use the Compose development keys or
encryption keys in production; provide secret-managed values instead.

## Configuration

The service requires:

- `POSTGRES_DSN`
- `RSA_PRIVATE_KEY_PEM`
- `RSA_PUBLIC_KEY_PEM`
- `EMAIL_ENCRYPTION_KEY`
- `EMAIL_LOOKUP_KEY`

Optional listener settings default to `SERVER_PORT=8080` and
`SERVER_PORT_TLS=8443` inside the container. `docker-compose.yaml` maps these
to host ports `9999` and `8444` by default.

## Database and generated code rules

- Add or change HTTP contracts in the module's `api/http/openapi.yaml`, then
  regenerate the corresponding `openapi.gen.go` files with the repository's
  `oapi-codegen` configuration.
- Treat each `api/http/openapi.yaml` as a hand-maintained, human-readable
  source contract. Keep mappings in block style with one property per line;
  keep parameters, required fields, and other sequences as one item per
  indented block; and avoid compact `{ ... }` flow mappings for new or changed
  API definitions.
- After adding or changing an endpoint, format the OpenAPI source before
  running code generation, then inspect the diff to confirm that only the
  intended contract changed. Never edit `openapi.gen.go` manually: it is a
  generated transport artifact derived from the formatted OpenAPI source.
- Add or change SQL in `adapters/db/queries/*.sql`, then regenerate sqlc output
  under `adapters/db/dbmodels/`.
- Keep migrations numbered and embedded by the owning module.
- Do not put business rules in HTTP handlers or database adapters.

## Development commands

```sh
# Start PostgreSQL only for local Go development
docker compose up -d postgres

# From dealership/
go test ./...
go run ./cmd
```

The service automatically applies both module migration sets during startup.

## Completion checks

- `go test ./...` passes from `dealership/`.
- Go changes are formatted with `gofmt`.
- OpenAPI sources remain expanded and human-readable, and OpenAPI/sqlc
  generated artifacts are regenerated when their sources change.
- Docker-dependent changes are checked with `docker compose config` and a
  Compose startup/health check.
