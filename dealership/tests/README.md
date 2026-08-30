# Component tests

The component suite starts the composed dealership service with a real PostgreSQL database and sends HTTP requests through its public routes. It is opt-in so unit tests do not require Docker or a database.

Use a dedicated, disposable database because the suite creates test users and dealership data. It does not drop schemas or delete existing data. The database must be empty on the first run; subsequent runs reuse the component-test superadmin created by the suite.

```sh
docker compose up -d postgres
cd dealership
COMPONENT_TEST=1 \
  COMPONENT_TEST_POSTGRES_DSN='postgres://postgres:very-secret@localhost:5432/ht47?sslmode=disable' \
  go test ./tests -count=1
```

On first use, the suite creates `component-superadmin@example.test` with password `ComponentPass1@`. Re-running against the same dedicated database reuses that account and generates unique data for every other fixture.
