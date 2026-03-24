# docker-backup

Docker container for backing up volumes and mount points using [restic](https://restic.net/) + [rclone](https://rclone.org/).

## Features

- **Incremental, deduplicated, encrypted backups** via restic
- **Cloud storage support** via rclone (Google Drive, S3, B2, SFTP, etc.)
- **Multiple backup targets** with independent configuration
- **Pre/post hooks** for safe database backups (e.g., SQLite `.backup`)
- **Cron scheduling** with configurable expressions
- **Retention policies** (daily/weekly/monthly/yearly)
- **Notifications** on failure (webhook, Gotify)
- **Docker healthcheck** based on last backup status

## Quick start

1. Create `config.yml` based on `config.example.yml`
2. Set up rclone config: `rclone config` → save as `rclone.conf`
3. Run:

```bash
RESTIC_PASSWORD=your-secret docker compose up -d
```

## Configuration

See [config.example.yml](config.example.yml) for all options.

### Targets

Each target defines a path to back up. Volumes and bind mounts should be mounted read-only where possible.

```yaml
targets:
  - name: "my-app"
    path: "/data/my-app"

  - name: "my-database"
    path: "/data/my-db"
    pre_hook: "sqlite3 /data/my-db/app.db '.backup /data/my-db/app-safe.db'"
    backup_path: "/data/my-db/app-safe.db"
    post_hook: "rm -f /data/my-db/app-safe.db"
```

### SQLite databases

Use `pre_hook` with `sqlite3 .backup` to create a consistent copy before backup. The container includes `sqlite3` for this purpose. Note: the volume needs read-write access for the safe copy.

## Restore

Exec into the container and use the restore helper:

```bash
# List all snapshots
docker exec docker-backup restore.sh

# List snapshots for a specific target
docker exec docker-backup restore.sh -t my-app

# List files in a snapshot
docker exec docker-backup restore.sh -t my-app -s latest -l

# Restore latest snapshot to /restore/my-app
docker exec docker-backup restore.sh -t my-app -s latest

# Restore to a custom path
docker exec docker-backup restore.sh -t my-app -s latest -d /custom/path
```

Then copy the restored files where needed:

```bash
docker cp docker-backup:/restore/my-app ./restored-data
```

## Manual backup

Trigger a backup outside of the cron schedule:

```bash
docker exec docker-backup backup.sh
```

## Health check

The container reports healthy/unhealthy based on the last backup result. Check with:

```bash
docker inspect --format='{{.State.Health.Status}}' docker-backup
```
