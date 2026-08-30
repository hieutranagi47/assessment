#!/bin/bash
# PostgreSQL restore script
# Usage: ./docker/postgresql/restore.sh <backup_file.sql>

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <backup_file.sql>"
  echo "Example: $0 ./docker/postgresql/backups/backup_20240115_120000.sql"
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: Backup file not found: $BACKUP_FILE"
  exit 1
fi

DB_NAME="${POSTGRES_DB:-ht47}"
DB_USER="${POSTGRES_USER:-postgres}"

echo "Restoring PostgreSQL from: $BACKUP_FILE"
echo "Target database: $DB_NAME"
echo "This will drop and recreate the database. Continue? (y/n)"
read -r response

if [ "$response" != "y" ]; then
  echo "Restore cancelled."
  exit 0
fi

# Drop existing database and recreate
docker compose exec -T postgres psql -U "$DB_USER" -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
docker compose exec -T postgres psql -U "$DB_USER" -c "CREATE DATABASE \"$DB_NAME\";"

# Restore backup
docker compose exec -T postgres psql -U "$DB_USER" "$DB_NAME" < "$BACKUP_FILE"

echo "Restore completed successfully!"
