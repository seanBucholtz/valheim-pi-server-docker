#!/bin/sh
# Periodic backup loop for the `backup` container.
set -eu

HOURS="${BACKUP_INTERVAL_HOURS:-6}"
echo "[$(date '+%F %T')] [backup] every ${HOURS}h, keeping ${BACKUP_KEEP:-28} archives"

while true; do
    sleep "$((HOURS * 3600))"
    /bin/sh /scripts/backup-once.sh || echo "[$(date '+%F %T')] [backup] snapshot FAILED"
done
