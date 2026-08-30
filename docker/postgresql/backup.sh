#!/bin/bash
# PostgreSQL backup script
# Usage: ./docker/postgresql/backup.sh

set -e

BACKUP_DIR="./docker/postgresql/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.sql"

echo "Starting PostgreSQL backup..."

# Get database credentials from docker-compose or env
DB_NAME="${POSTGRES_DB:-ht47}"
DB_USER="${POSTGRES_USER:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-very-secret}"

# Create backup
docker compose exec -T postgres pg_dump -U "$DB_USER" "$DB_NAME" > "$BACKUP_FILE"

echo "Backup completed: $BACKUP_FILE"
echo "File size: $(du -h $BACKUP_FILE | cut -f1)"
