# PostgreSQL Backups

This directory contains PostgreSQL database backups that can be restored on any machine running this project.

## Workflow

### On Source Machine (Create Backup)
1. Ensure services are running: `docker compose up -d`
2. Create a backup:
   ```bash
   chmod +x ./docker/postgresql/backup.sh
   ./docker/postgresql/backup.sh
   ```
3. A timestamped SQL file will be created in `./docker/postgresql/backups/`
4. Commit and push to repo:
   ```bash
   git add docker/postgresql/backups/
   git commit -m "Add PostgreSQL backup"
   git push
   ```

### On Target Machine (Restore Backup)
1. Pull the repo with backup files
2. Start services:
   ```bash
   docker compose up -d
   ```
3. Wait for PostgreSQL to be healthy (check logs):
   ```bash
   docker compose logs postgres
   ```
4. Restore the backup:
   ```bash
   chmod +x ./docker/postgresql/restore.sh
   ./docker/postgresql/restore.sh ./docker/postgresql/backups/backup_YYYYMMDD_HHMMSS.sql
   ```
5. Verify restoration:
   ```bash
   docker compose exec postgres psql -U postgres -d ht47 -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';"
   ```

## Notes
- Backups are plain SQL text files (human-readable, git-friendly)
- Keep only essential backups in repo (large files can bloat git history)
- For production, consider using `pg_dump` with compression: `pg_dump -Fc` and `pg_restore`
- Never commit backups with sensitive data unencrypted
