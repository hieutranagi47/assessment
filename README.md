# Dealership service

A Go HTTP service for authentication and dealership appointment scheduling.
The application is in [`dealership/`](dealership/), with PostgreSQL provided
by Docker Compose.

## Some note

- I reuse the auth module that I created it for my testing, then I ignored the system design for the module, and if I have a chance to demonstrate this project in the next interview section, I'll explain it later. I just focus on the core feature of the assessment, `appointment_scheduler` module.

## Prerequisites

- Docker Desktop or Docker Engine with the Compose plugin
- Git
- Go 1.26.5 only if you want to run or test the Go code outside Docker

## Run locally with Docker

From the repository root:

```sh
docker compose up --build -d
```

This starts:

- PostgreSQL on `localhost:5432`
- the dealership service on HTTP `localhost:9999`
- the dealership service on HTTPS `localhost:8444`

The service waits for PostgreSQL to become healthy, then applies the embedded
`auth` and `appointment_scheduler` migrations automatically.

Check that the service is running:

```sh
curl -i http://localhost:9999/health
docker compose ps
docker compose logs -f dealership
```

## Load deterministic development fixtures

After PostgreSQL is healthy and the service has applied its migrations, load
the fixtures from the Go module directory. The command runs the seed executable
in the Compose service environment, so it uses the same PostgreSQL and email
configuration without printing either:

```sh
cd dealership
task seed
```

The command uses the same environment configuration as the service and is
manual-only; it never runs at startup, during migrations, or in tests. It is
transactional and can be run repeatedly without changing fixture identities or
duplicating rows. It creates 80 auth accounts, from `abc1@email.com` through
`abc80@email.com`; their default development password is `Abc@6789`. Set
`SEED_PASSWORD` to use a different password before the
first seed run. The scheduler login-capable employees use auth accounts
`abc6@email.com` through `abc80@email.com`. Accounts `abc6@email.com`
through `abc30@email.com` are dealership administrators, staff, and dealers;
`abc31@email.com` through `abc80@email.com` are technicians. Every seeded
technician has the scheduler `technician` role and can log in.

`/health` returns `204 No Content`. Interactive auth API documentation is
available at [http://localhost:9999/auth/docs/](http://localhost:9999/auth/docs/).
The HTTPS listener uses a development self-signed certificate, so use `-k`
with curl when testing it:

```sh
curl -k -i https://localhost:8444/health
```

## Run and test the Go service without the app container

You can run only PostgreSQL in Docker and run Go locally:

```sh
docker compose up -d postgres
cd dealership
go test ./...
go run ./cmd
```

The local process uses HTTP port `8080` and HTTPS port `8443` by default. Set
the required environment variables before `go run ./cmd`; the Compose file
contains development values that can be copied for local use. When the service
is run locally, use `POSTGRES_DSN` with `localhost`, for example:

```sh
export POSTGRES_DSN='postgres://postgres:very-secret@localhost:5432/ht47?sslmode=disable'
```

## Configuration overrides

Compose supplies development defaults for the database, RSA key pair, email
encryption keys, and container listener ports. Override host ports or database
settings with environment variables when needed:

```sh
POSTGRES_PORT=55432 SERVER_PORT=9000 SERVER_PORT_TLS=9443 \
  docker compose up --build -d
```

The application still listens on container ports `8080` and `8443`; these
variables change the host-side mappings. For production, replace all
development secrets in `docker-compose.yaml` with secret-managed values.

## Stop the service

```sh
docker compose down
```

To remove the local PostgreSQL data volume as well, use the explicit command
below. This deletes local development data:

```sh
docker compose down -v
```

## Project architecture

The service is composed from the `auth` and `appointment_scheduler` bounded
contexts. Each context separates `domain`, `app`, `adapters`, and `api/http`
packages; the common module provides shared infrastructure. See
[`AGENT.MD`](AGENT.MD) for the full package map, dependency rules, generated
code workflow, and development conventions.
