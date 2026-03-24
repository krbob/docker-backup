#!/usr/bin/env bash
set -euo pipefail

CONFIG="/run/docker-backup/config.yml"
STATUS_FILE="/var/run/docker-backup/last-run"
LOCK_FILE="/var/run/docker-backup/backup.lock"
HISTORY_FILE="/var/log/docker-backup/history.jsonl"
LOG="[docker-backup]"
DRY_RUN=false

if [ "${1:-}" = "--dry-run" ] || [ "${1:-}" = "-n" ]; then
    DRY_RUN=true
    echo "$LOG DRY RUN — no changes will be made"
fi

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
START_TIME=$(date +%s)
TIMESTAMP=$(date -Iseconds)
TARGET_RESULTS=""

echo "$LOG Backup started at ${TIMESTAMP}"

for i in $(seq 0 $((TARGET_COUNT - 1))); do
    NAME=$(yq ".targets[$i].name" "$CONFIG")
    TARGET_PATH=$(yq ".targets[$i].path" "$CONFIG")
    PRE_HOOK=$(yq ".targets[$i].pre_hook // \"\"" "$CONFIG")
    POST_HOOK=$(yq ".targets[$i].post_hook // \"\"" "$CONFIG")
    BACKUP_PATH=$(yq ".targets[$i].backup_path // \"${TARGET_PATH}\"" "$CONFIG")
    TARGET_START=$(date +%s)

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
        if [ "$DRY_RUN" = false ]; then
            if ! eval "$PRE_HOOK"; then
                echo "$LOG [$NAME] Pre-hook failed, skipping target"
                FAIL=1
                TARGET_RESULTS="${TARGET_RESULTS}{\"name\":\"${NAME}\",\"status\":\"pre_hook_failed\",\"duration\":$(($(date +%s) - TARGET_START))},"
                continue
            fi
        else
            echo "$LOG [$NAME] Would run pre-hook: ${PRE_HOOK}"
        fi
    fi

    # Backup
    if [ "$DRY_RUN" = true ]; then
        echo "$LOG [$NAME] Would backup: ${BACKUP_PATH}"
        restic backup "$BACKUP_PATH" --tag "$NAME" "${EXCLUDE_ARGS[@]+"${EXCLUDE_ARGS[@]}"}" --dry-run 2>&1 || true
        TARGET_RESULTS="${TARGET_RESULTS}{\"name\":\"${NAME}\",\"status\":\"dry_run\",\"duration\":0},"
    else
        BACKUP_OUTPUT=$(restic backup "$BACKUP_PATH" --tag "$NAME" "${EXCLUDE_ARGS[@]+"${EXCLUDE_ARGS[@]}"}" --json 2>&1 || true)
        if echo "$BACKUP_OUTPUT" | grep -q '"message_type":"summary"'; then
            SNAPSHOT_SIZE=$(echo "$BACKUP_OUTPUT" | grep '"message_type":"summary"' | jq -r '.total_bytes_processed // 0')
            FILES_NEW=$(echo "$BACKUP_OUTPUT" | grep '"message_type":"summary"' | jq -r '.files_new // 0')
            FILES_CHANGED=$(echo "$BACKUP_OUTPUT" | grep '"message_type":"summary"' | jq -r '.files_changed // 0')
            echo "$LOG [$NAME] Backup complete (${FILES_NEW} new, ${FILES_CHANGED} changed, ${SNAPSHOT_SIZE} bytes)"
            TARGET_RESULTS="${TARGET_RESULTS}{\"name\":\"${NAME}\",\"status\":\"ok\",\"bytes\":${SNAPSHOT_SIZE},\"files_new\":${FILES_NEW},\"files_changed\":${FILES_CHANGED},\"duration\":$(($(date +%s) - TARGET_START))},"
        else
            echo "$LOG [$NAME] Backup failed"
            echo "$BACKUP_OUTPUT" | grep -v '"message_type":"status"' || true
            FAIL=1
            TARGET_RESULTS="${TARGET_RESULTS}{\"name\":\"${NAME}\",\"status\":\"failed\",\"duration\":$(($(date +%s) - TARGET_START))},"
        fi
    fi

    # Post-hook
    if [ -n "$POST_HOOK" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo "$LOG [$NAME] Would run post-hook: ${POST_HOOK}"
        else
            eval "$POST_HOOK" || echo "$LOG [$NAME] Post-hook failed (non-fatal)"
        fi
    fi
done

# Retention
if [ "$DRY_RUN" = false ]; then
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
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Write history log
if [ "$DRY_RUN" = false ]; then
    RESULT="ok"
    [ "$FAIL" -ne 0 ] && RESULT="error"
    # Remove trailing comma from target results
    TARGET_RESULTS=$(echo "$TARGET_RESULTS" | sed 's/,$//')
    echo "{\"timestamp\":\"${TIMESTAMP}\",\"status\":\"${RESULT}\",\"duration\":${DURATION},\"targets\":[${TARGET_RESULTS}]}" >> "$HISTORY_FILE"
fi

# Status
if [ "$DRY_RUN" = true ]; then
    echo "$LOG Dry run complete"
elif [ "$FAIL" -eq 0 ]; then
    echo "OK $(date -Iseconds)" > "$STATUS_FILE"
    echo "$LOG Backup completed successfully (${DURATION}s)"

    NOTIFY_SUCCESS=$(yq '.notifications.on_success // false' "$CONFIG")
    if [ "$NOTIFY_SUCCESS" = "true" ]; then
        /usr/local/bin/notify.sh "Backup completed successfully (${DURATION}s)"
    fi
else
    echo "FAIL $(date -Iseconds)" > "$STATUS_FILE"
    echo "$LOG Backup completed with errors (${DURATION}s)"

    NOTIFY_FAILURE=$(yq '.notifications.on_failure // false' "$CONFIG")
    if [ "$NOTIFY_FAILURE" = "true" ]; then
        /usr/local/bin/notify.sh "Backup completed with errors (${DURATION}s)"
    fi
fi
