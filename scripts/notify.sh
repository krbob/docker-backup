#!/usr/bin/env bash
set -euo pipefail

CONFIG="/run/docker-backup/config.yml"
MSG="${1:-Backup notification}"
LOG="[docker-backup]"

TYPE=$(yq '.notifications.type // ""' "$CONFIG")

if [ -z "$TYPE" ] || [ "$TYPE" = "null" ]; then
    exit 0
fi

case "$TYPE" in
    webhook)
        URL=$(yq '.notifications.webhook_url' "$CONFIG")
        if [ -n "$URL" ] && [ "$URL" != "null" ]; then
            curl -sf -X POST -H "Content-Type: application/json" \
                -d "{\"text\":\"${MSG}\"}" "$URL" || \
                echo "$LOG Webhook notification failed"
        fi
        ;;
    gotify)
        URL=$(yq '.notifications.gotify_url' "$CONFIG")
        TOKEN=$(yq '.notifications.gotify_token' "$CONFIG")
        if [ -n "$URL" ] && [ "$URL" != "null" ]; then
            curl -sf -X POST "${URL}/message?token=${TOKEN}" \
                -F "title=docker-backup" \
                -F "message=${MSG}" || \
                echo "$LOG Gotify notification failed"
        fi
        ;;
    *)
        echo "$LOG Unknown notification type: ${TYPE}"
        ;;
esac
