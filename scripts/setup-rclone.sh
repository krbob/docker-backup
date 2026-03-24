#!/usr/bin/env bash
set -euo pipefail

RCLONE_CONF="/config/rclone.conf"
LOG="[docker-backup]"

echo "$LOG Starting rclone configuration..."
echo "$LOG"
echo "$LOG This helper will guide you through setting up a cloud storage remote."
echo "$LOG The configuration will be saved to ${RCLONE_CONF}."
echo "$LOG"

# Check if config volume is writable
if ! touch "${RCLONE_CONF}.test" 2>/dev/null; then
    echo "$LOG ERROR: Cannot write to /config/"
    echo "$LOG Make sure /config/ is mounted as a writable volume (not read-only)."
    echo "$LOG"
    echo "$LOG Example: -v /opt/homelab/config/backup:/config"
    exit 1
fi
rm -f "${RCLONE_CONF}.test"

# Write config to a temp file first, then copy (avoids bind mount rename issues)
TEMP_CONF="/tmp/rclone-setup.conf"

# Copy existing config if present
if [ -f "$RCLONE_CONF" ] && [ -s "$RCLONE_CONF" ]; then
    cp "$RCLONE_CONF" "$TEMP_CONF"
fi

echo "$LOG Running rclone config interactively..."
echo "$LOG When asked for authorization, choose 'No' for web browser and follow"
echo "$LOG the instructions to authorize on a machine with a browser."
echo ""

rclone config --config "$TEMP_CONF"

# Copy result back (works with bind mounts, unlike rename)
if [ -f "$TEMP_CONF" ]; then
    cp "$TEMP_CONF" "$RCLONE_CONF"
    rm -f "$TEMP_CONF"
    echo ""
    echo "$LOG Configuration saved to ${RCLONE_CONF}"
    echo "$LOG Configured remotes:"
    rclone listremotes --config "$RCLONE_CONF"
else
    echo "$LOG No configuration was saved."
fi
