#!/usr/bin/env bash
set -euo pipefail

CONFIG="/run/docker-backup/config.yml"
STATUS_FILE="/var/run/docker-backup/last-run"
LOCK_FILE="/var/run/docker-backup/backup.lock"
LOG="[docker-backup]"

# Prevent concurrent runs
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$LOG Backup already running, skipping"
    exit 0
fi

# Load config
REPO=$(yq '.repository.location' "$CONFIG")
RESTIC_PASSWORD=$(yq '.repository.password' "$CONFIG")
RCLONE_CONFIG=$(yq '.rclone_config // "/config/rclone.conf"' "$CONFIG")
export RESTIC_PASSWORD RESTIC_REPOSITORY="$REPO" RCLONE_CONFIG

TARGET_COUNT=$(yq '.targets | length' "$CONFIG")
FAIL=0
TIMESTAMP=$(date -Iseconds)

echo "$LOG Backup started at ${TIMESTAMP}"

for i in $(seq 0 $((TARGET_COUNT - 1))); do
    NAME=$(yq ".targets[$i].name" "$CONFIG")
    TARGET_PATH=$(yq ".targets[$i].path" "$CONFIG")
    PRE_HOOK=$(yq ".targets[$i].pre_hook // \"\"" "$CONFIG")
    POST_HOOK=$(yq ".targets[$i].post_hook // \"\"" "$CONFIG")
    BACKUP_PATH=$(yq ".targets[$i].backup_path // \"${TARGET_PATH}\"" "$CONFIG")

    echo "$LOG [$NAME] Starting backup of ${BACKUP_PATH}"

    # Build exclude args
    EXCLUDE_ARGS=()
    EXCLUDE_COUNT=$(yq ".targets[$i].exclude | length" "$CONFIG")
    if [ "$EXCLUDE_COUNT" != "0" ] && [ "$EXCLUDE_COUNT" != "null" ]; then
        for j in $(seq 0 $((EXCLUDE_COUNT - 1))); do
            PATTERN=$(yq ".targets[$i].exclude[$j]" "$CONFIG")
            EXCLUDE_ARGS+=(--exclude "$PATTERN")
        done
    fi

    # Pre-hook
    if [ -n "$PRE_HOOK" ]; then
        echo "$LOG [$NAME] Running pre-hook..."
        if ! eval "$PRE_HOOK"; then
            echo "$LOG [$NAME] Pre-hook failed, skipping target"
            FAIL=1
            continue
        fi
    fi

    # Backup
    if ! restic backup "$BACKUP_PATH" --tag "$NAME" "${EXCLUDE_ARGS[@]+"${EXCLUDE_ARGS[@]}"}"; then
        echo "$LOG [$NAME] Backup failed"
        FAIL=1
    else
        echo "$LOG [$NAME] Backup complete"
    fi

    # Post-hook
    if [ -n "$POST_HOOK" ]; then
        eval "$POST_HOOK" || echo "$LOG [$NAME] Post-hook failed (non-fatal)"
    fi
done

# Retention
echo "$LOG Applying retention policy..."
KEEP_DAILY=$(yq '.retention.keep_daily // 7' "$CONFIG")
KEEP_WEEKLY=$(yq '.retention.keep_weekly // 4' "$CONFIG")
KEEP_MONTHLY=$(yq '.retention.keep_monthly // 6' "$CONFIG")
KEEP_YEARLY=$(yq '.retention.keep_yearly // 2' "$CONFIG")

restic forget \
    --keep-daily "$KEEP_DAILY" \
    --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY" \
    --keep-yearly "$KEEP_YEARLY" \
    --prune || { echo "$LOG Retention pruning failed"; FAIL=1; }

# Status
if [ "$FAIL" -eq 0 ]; then
    echo "OK $(date -Iseconds)" > "$STATUS_FILE"
    echo "$LOG Backup completed successfully"

    NOTIFY_SUCCESS=$(yq '.notifications.on_success // false' "$CONFIG")
    if [ "$NOTIFY_SUCCESS" = "true" ]; then
        /usr/local/bin/notify.sh "Backup completed successfully"
    fi
else
    echo "FAIL $(date -Iseconds)" > "$STATUS_FILE"
    echo "$LOG Backup completed with errors"

    NOTIFY_FAILURE=$(yq '.notifications.on_failure // false' "$CONFIG")
    if [ "$NOTIFY_FAILURE" = "true" ]; then
        /usr/local/bin/notify.sh "Backup completed with errors"
    fi
fi
