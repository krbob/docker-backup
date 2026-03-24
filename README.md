# docker-backup

Docker container for backing up volumes and mount points using [restic](https://restic.net/) + [rclone](https://rclone.org/).

## Features

- **Incremental, deduplicated, encrypted backups** via restic
- **Cloud storage support** via rclone (Google Drive, S3, B2, SFTP, etc.)
- **Multiple backup targets** with independent configuration
- **Pre/post hooks** for safe database backups (e.g., SQLite `.backup`)
- **Cron scheduling** with configurable expressions
- **Retention policies** (daily/weekly/monthly/yearly)
- **Repository integrity verification** (periodic `restic check`)
- **Staleness detection** — healthcheck catches stopped/stale backups
- **Backup history log** with duration, size, and per-target details
- **Dry run mode** to preview what would be backed up
- **Notifications** on failure (webhook, Gotify)
- **Docker healthcheck** based on last backup status and staleness

## Quick start

1. Set up rclone (for cloud storage):

```bash
docker run --rm -it \
  --entrypoint setup-rclone.sh \
  -v /opt/homelab/config/backup:/config \
  ghcr.io/krbob/docker-backup:latest
```

2. Create `config.yml` based on `config.example.yml`

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

### Repository verification

By default, `restic check` runs weekly (Sunday 04:00) to verify repository integrity. Configure or disable:

```yaml
verify:
  enabled: false
  # schedule: "0 4 * * 0"
```

## Restore

Exec into the container and use the restore helper:

```bash
# List all snapshots
docker exec backup restore.sh

# List snapshots for a specific target
docker exec backup restore.sh -t my-app

# List files in a snapshot
docker exec backup restore.sh -t my-app -s latest -l

# Restore latest snapshot to /restore/my-app
docker exec backup restore.sh -t my-app -s latest

# Restore to a custom path
docker exec backup restore.sh -t my-app -s latest -d /custom/path
```

Then copy the restored files where needed:

```bash
docker cp backup:/restore/my-app/data/my-app/. /opt/homelab/data/my-app/
```

## Manual backup

```bash
docker exec backup backup.sh
```

## Dry run

Preview what would be backed up without making changes:

```bash
docker exec backup backup.sh --dry-run
```

## Status

View backup status, history, and repository info:

```bash
docker exec backup status.sh
```

## Health check

The container reports unhealthy when:
- The last backup failed
- No backup has run for 2x the scheduled interval (staleness detection)

```bash
docker inspect --format='{{.State.Health.Status}}' backup
```

## Rclone setup

Interactive helper for configuring cloud storage remotes:

```bash
docker run --rm -it \
  --entrypoint setup-rclone.sh \
  -v /opt/homelab/config/backup:/config \
  ghcr.io/krbob/docker-backup:latest
```

This avoids the bind-mount rename issues that occur with `rclone config` directly.
