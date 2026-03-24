#!/usr/bin/env bash
set -euo pipefail

CONFIG="/run/docker-backup/config.yml"
LOG="[docker-backup]"

# Load config
REPO=$(yq '.repository.location' "$CONFIG")
RESTIC_PASSWORD=$(yq '.repository.password' "$CONFIG")
RCLONE_CONFIG=$(yq '.rclone_config // "/config/rclone.conf"' "$CONFIG")
export RESTIC_PASSWORD RESTIC_REPOSITORY="$REPO" RCLONE_CONFIG

echo "$LOG Verifying repository integrity..."

if restic check 2>&1; then
    echo "$LOG Repository integrity OK"
else
    echo "$LOG Repository integrity check FAILED"
    NOTIFY_FAILURE=$(yq '.notifications.on_failure // false' "$CONFIG")
    if [ "$NOTIFY_FAILURE" = "true" ]; then
        /usr/local/bin/notify.sh "Repository integrity check FAILED — backup data may be corrupted"
    fi
    exit 1
fi
