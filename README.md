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
- Prometheus on [localhost:9090](http://localhost:9090)
- Grafana on [localhost:3000](http://localhost:3000) (`admin` / `admin`)
- Jaeger on [localhost:16686](http://localhost:16686)

The service waits for PostgreSQL to become healthy, then applies the embedded
`auth` and `appointment_scheduler` migrations automatically.

Check that the service is running:

```sh
curl -i http://localhost:9999/health
curl -i http://localhost:9999/metrics
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

## Start testing

1. Open the appointment_scheduler.dealership to pick one dealership_id, see the dealership timezone.

2. Get the employees of the dealership

```sql
SELECT
  u.user_id,
  u.auth_user_id,
  u.name,
  u.email,
  u.phone,
  u.is_active,
  u.dealership_id,
  d.code AS dealership_code,
  d.name AS dealership_name,
  r.code AS role_code,
  r.name AS role_name
FROM appointment_scheduler.users AS u
LEFT JOIN appointment_scheduler.dealerships AS d
    ON d.dealership_id = u.dealership_id
LEFT JOIN appointment_scheduler.user_roles AS ur
    ON ur.user_id = u.user_id
   AND ur.deleted_at IS NULL
LEFT JOIN appointment_scheduler.roles AS r
    ON r.role_id = ur.role_id
   AND r.deleted_at IS NULL
WHERE u.dealership_id = 'DEALERSHIP_ID'
  AND u.deleted_at IS NULL
ORDER BY u.name, r.code;
```

From the sql result, take an admin account and it its' `auth_user_id`

3. Get the `auth.user_id` = the above `auth_user_id` to see it's email.

4. Use Postman to signin with email is the above account email, password: `Abc@6789`

```json
# [POST] localhost:9999/auth/v1/sign-in
{
  "email": "abc@email.com",
  "password": "Tqh@6879"
}
```
The API will response the access_token in the response body (There are a refresh_token on the http cookie only but you don't need it now). Note that the token will expires in 15 minutes. I don't bring the access_token expires time into environment variable yet. and you can update it in `dealership/modules/auth/adapters/token/issuer.go` file `accessLifetime  = 15 * time.Minute`
Copy the `access_token` to test other apis.

5. Get work schedule of all all employees of the above dealership by this api

```bash
# [GET] http://localhost:9999/appointment-scheduler/v1/dealerships/<Dealership_id>/technician-schedules?date=2026-09-16
```

6. Getting available service bays of that service_types

```bash

```

7. Booking a service.

## Tracing log

Access the Jaeger at http://localhost:16686, select the `dealership` service to see it.

![Jaeger screenshot](tracing.png)
