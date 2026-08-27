package common

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"path"
	"sort"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const migrationLockID int64 = 0x4153534553534D54 // "ASSESSMT"

// MigrateDatabaseUp applies embedded up migrations in schema. Each bounded
// context has its own schema and migration history, even when modules share a
// PostgreSQL database and connection pool.
func MigrateDatabaseUp(ctx context.Context, database *pgxpool.Pool, schema string, migrations fs.FS, migrationsDir string) error {
	if schema == "" {
		return errors.New("migration schema is required")
	}
	if err := database.Ping(ctx); err != nil {
		return fmt.Errorf("ping PostgreSQL database: %w", err)
	}

	files, err := fs.Glob(migrations, path.Join(migrationsDir, "*.up.sql"))
	if err != nil {
		return fmt.Errorf("find migrations: %w", err)
	}
	sort.Strings(files)

	conn, err := database.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("acquire migration connection: %w", err)
	}
	defer conn.Release()
	if _, err := conn.Exec(ctx, "SELECT pg_advisory_lock($1)", migrationLockID); err != nil {
		return fmt.Errorf("lock migrations: %w", err)
	}
	defer func() { _, _ = conn.Exec(context.Background(), "SELECT pg_advisory_unlock($1)", migrationLockID) }()

	if _, err := conn.Exec(ctx, "CREATE SCHEMA IF NOT EXISTS "+pgx.Identifier{schema}.Sanitize()); err != nil {
		return fmt.Errorf("create schema: %w", err)
	}
	migrationTable := pgx.Identifier{schema, "schema_migrations"}.Sanitize()
	if _, err := conn.Exec(ctx, `CREATE TABLE IF NOT EXISTS `+migrationTable+` (
		version bigint NOT NULL PRIMARY KEY,
		dirty boolean NOT NULL
	)`); err != nil {
		return fmt.Errorf("create migration table: %w", err)
	}

	current, err := migrationVersion(ctx, conn, migrationTable)
	if err != nil {
		return err
	}
	for _, file := range files {
		version, err := migrationFileVersion(path.Base(file))
		if err != nil {
			return err
		}
		if version <= current {
			continue
		}
		contents, err := fs.ReadFile(migrations, file)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", file, err)
		}
		if err := applyMigration(ctx, conn, schema, migrationTable, version, string(contents)); err != nil {
			return fmt.Errorf("apply migration %s: %w", file, err)
		}
		current = version
	}
	return nil
}

func migrationVersion(ctx context.Context, conn *pgxpool.Conn, migrationTable string) (int64, error) {
	var version int64
	var dirty bool
	err := conn.QueryRow(ctx, "SELECT version, dirty FROM "+migrationTable+" LIMIT 1").Scan(&version, &dirty)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("read migration version: %w", err)
	}
	if dirty {
		return 0, fmt.Errorf("database is at dirty migration version %d", version)
	}
	return version, nil
}

func applyMigration(ctx context.Context, conn *pgxpool.Conn, schema, migrationTable string, version int64, sql string) error {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, "SET LOCAL search_path TO "+pgx.Identifier{schema}.Sanitize()); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "DELETE FROM "+migrationTable); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "INSERT INTO "+migrationTable+" (version, dirty) VALUES ($1, TRUE)", version); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, sql, pgx.QueryExecModeSimpleProtocol); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, "UPDATE "+migrationTable+" SET dirty = FALSE WHERE version = $1", version); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func migrationFileVersion(name string) (int64, error) {
	prefix, _, found := strings.Cut(name, "_")
	if !found {
		return 0, fmt.Errorf("invalid migration filename %q", name)
	}
	version, err := strconv.ParseInt(prefix, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid migration filename %q: %w", name, err)
	}
	return version, nil
}
