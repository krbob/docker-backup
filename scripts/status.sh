#!/usr/bin/env bash
set -euo pipefail

CONFIG="/run/docker-backup/config.yml"
STATUS_FILE="/var/run/docker-backup/last-run"
HISTORY_FILE="/var/log/docker-backup/history.jsonl"
LOG="[docker-backup]"

LINES="${1:-10}"

# Load config
REPO=$(yq '.repository.location' "$CONFIG")
RESTIC_PASSWORD=$(yq '.repository.password' "$CONFIG")
RCLONE_CONFIG=$(yq '.rclone_config // "/config/rclone.conf"' "$CONFIG")
export RESTIC_PASSWORD RESTIC_REPOSITORY="$REPO" RCLONE_CONFIG

echo "=== Backup Status ==="
echo ""

# Last run
if [ -f "$STATUS_FILE" ]; then
    echo "Last run: $(cat "$STATUS_FILE")"
else
    echo "Last run: no backup has run yet"
fi
echo ""

# Repository info
echo "Repository: $REPO"
SNAPSHOT_COUNT=$(restic snapshots --json 2>/dev/null | jq 'length' 2>/dev/null || echo "?")
echo "Snapshots:  $SNAPSHOT_COUNT"

if [ "$SNAPSHOT_COUNT" != "?" ] && [ "$SNAPSHOT_COUNT" != "0" ]; then
    echo ""
    echo "=== Latest Snapshots ==="
    restic snapshots --last 2>/dev/null || true
fi

# History
if [ -f "$HISTORY_FILE" ]; then
    TOTAL=$(wc -l < "$HISTORY_FILE")
    echo ""
    echo "=== Recent History (last ${LINES} of ${TOTAL}) ==="
    tail -n "$LINES" "$HISTORY_FILE" | while IFS= read -r line; do
        TS=$(echo "$line" | jq -r '.timestamp')
        ST=$(echo "$line" | jq -r '.status')
        DUR=$(echo "$line" | jq -r '.duration')
        TARGETS=$(echo "$line" | jq -r '[.targets[].name] | join(", ")')
        echo "  ${TS}  ${ST}  ${DUR}s  [${TARGETS}]"
    done
fi
