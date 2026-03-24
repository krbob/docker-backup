#!/usr/bin/env bash
set -euo pipefail

CONFIG="/run/docker-backup/config.yml"
LOG="[docker-backup]"

# Load config
REPO=$(yq '.repository.location' "$CONFIG")
RESTIC_PASSWORD=$(yq '.repository.password' "$CONFIG")
RCLONE_CONFIG=$(yq '.rclone_config // "/config/rclone.conf"' "$CONFIG")
export RESTIC_PASSWORD RESTIC_REPOSITORY="$REPO" RCLONE_CONFIG

usage() {
    cat <<EOF
Usage: restore.sh [OPTIONS]

Commands:
  restore.sh                              List all snapshots
  restore.sh -t <target>                  List snapshots for a target
  restore.sh -t <target> -s <snapshot>    Restore snapshot to /restore/<target>
  restore.sh -t <target> -s <snapshot> -d <path>  Restore to custom path

Options:
  -t, --target    Target name (tag)
  -s, --snapshot  Snapshot ID or "latest"
  -d, --dest      Restore destination (default: /restore/<target>)
  -l, --ls        List files in snapshot instead of restoring
  -h, --help      Show this help
EOF
}

TARGET=""
SNAPSHOT=""
DEST=""
LIST_FILES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--target)   TARGET="$2"; shift 2 ;;
        -s|--snapshot) SNAPSHOT="$2"; shift 2 ;;
        -d|--dest)     DEST="$2"; shift 2 ;;
        -l|--ls)       LIST_FILES=true; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# No args: list all snapshots
if [ -z "$TARGET" ] && [ -z "$SNAPSHOT" ]; then
    restic snapshots
    exit 0
fi

# Target only: list snapshots for that target
if [ -n "$TARGET" ] && [ -z "$SNAPSHOT" ]; then
    restic snapshots --tag "$TARGET"
    exit 0
fi

# Snapshot specified
if [ -z "$TARGET" ]; then
    echo "Error: --target is required when specifying --snapshot"
    exit 1
fi

TAG_ARGS=(--tag "$TARGET")

# List files mode
if [ "$LIST_FILES" = true ]; then
    restic ls "$SNAPSHOT" "${TAG_ARGS[@]}"
    exit 0
fi

# Restore
DEST="${DEST:-/restore/${TARGET}}"
mkdir -p "$DEST"

echo "$LOG Restoring snapshot ${SNAPSHOT} (target: ${TARGET}) to ${DEST}..."
restic restore "$SNAPSHOT" --target "$DEST" "${TAG_ARGS[@]}"
echo "$LOG Restore complete: ${DEST}"
