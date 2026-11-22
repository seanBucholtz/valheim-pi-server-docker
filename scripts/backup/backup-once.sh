#!/bin/sh
# Make one compressed snapshot of /data/worlds into /backups and prune old ones.
# Runs inside the alpine `backup` container (busybox sh).
set -eu

SRC_PARENT=/data
SRC_NAME=worlds
DEST=/backups
KEEP="${BACKUP_KEEP:-28}"

log() { echo "[$(date '+%F %T')] [backup] $*"; }

if [ -z "$(ls -A "$SRC_PARENT/$SRC_NAME" 2>/dev/null)" ]; then
    log "No world data yet, skipping."
    exit 0
fi

# Avoid snapshotting mid-save: wait until nothing changed for a minute (max ~10 min).
tries=0
while [ -n "$(find "$SRC_PARENT/$SRC_NAME" -type f -mmin -1 2>/dev/null | head -n1)" ]; do
    tries=$((tries + 1))
    [ "$tries" -gt 20 ] && { log "World keeps changing; taking snapshot anyway."; break; }
    sleep 30
done

stamp="$(date '+%Y%m%d-%H%M%S')"
tmp="$DEST/.worlds-$stamp.tar.gz.partial"
out="$DEST/worlds-$stamp.tar.gz"

nice -n 19 tar -czf "$tmp" -C "$SRC_PARENT" "$SRC_NAME"
mv "$tmp" "$out"
log "Wrote $(basename "$out") ($(du -h "$out" | cut -f1))"

# Prune: keep newest $KEEP archives.
# shellcheck disable=SC2012  # filenames are our own timestamped names
ls -1t "$DEST"/worlds-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
    rm -f "$old"
    log "Pruned $(basename "$old")"
done
