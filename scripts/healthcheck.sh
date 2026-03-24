#!/usr/bin/env bash
set -euo pipefail

STATUS_FILE="/var/run/docker-backup/last-run"
CONFIG="/run/docker-backup/config.yml"

# No backup yet — still starting
if [ ! -f "$STATUS_FILE" ]; then
    exit 0
fi

# Last backup failed
STATUS=$(cut -d' ' -f1 < "$STATUS_FILE")
if [ "$STATUS" != "OK" ]; then
    echo "Last backup failed"
    exit 1
fi

# Staleness check: if last-run is older than 2x schedule interval, unhealthy
if [ -f "$CONFIG" ]; then
    SCHEDULE=$(yq '.schedule // "0 3 * * *"' "$CONFIG")

    # Parse cron schedule to get interval in seconds (simplified: check hours/minutes fields)
    MINUTE=$(echo "$SCHEDULE" | awk '{print $1}')
    HOUR=$(echo "$SCHEDULE" | awk '{print $2}')
    DOM=$(echo "$SCHEDULE" | awk '{print $3}')

    # Default: assume daily (86400s), doubled = 172800s
    MAX_AGE=172800

    # If minute field is */N, interval is N minutes
    if echo "$MINUTE" | grep -qE '^\*/[0-9]+$'; then
        INTERVAL_MIN=$(echo "$MINUTE" | cut -d/ -f2)
        MAX_AGE=$((INTERVAL_MIN * 60 * 2))
    # If hour field is */N, interval is N hours
    elif echo "$HOUR" | grep -qE '^\*/[0-9]+$'; then
        INTERVAL_HR=$(echo "$HOUR" | cut -d/ -f2)
        MAX_AGE=$((INTERVAL_HR * 3600 * 2))
    # If dom field is */N, interval is N days
    elif echo "$DOM" | grep -qE '^\*/[0-9]+$'; then
        INTERVAL_DAY=$(echo "$DOM" | cut -d/ -f2)
        MAX_AGE=$((INTERVAL_DAY * 86400 * 2))
    fi

    LAST_RUN_TIME=$(stat -c %Y "$STATUS_FILE" 2>/dev/null || stat -f %m "$STATUS_FILE" 2>/dev/null)
    NOW=$(date +%s)
    AGE=$((NOW - LAST_RUN_TIME))

    if [ "$AGE" -gt "$MAX_AGE" ]; then
        echo "Backup stale: last run ${AGE}s ago, max ${MAX_AGE}s"
        exit 1
    fi
fi

exit 0
