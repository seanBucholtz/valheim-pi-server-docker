#!/usr/bin/env bash
# Restore the worlds directory from a snapshot archive. Run on the Pi:
#   ./scripts/restore.sh backups/worlds-20260115-180000.tar.gz
# The current worlds dir is kept as worlds.pre-restore-<timestamp>.
set -euo pipefail

archive="${1:-}"
[[ -f "$archive" ]] || { echo "usage: $0 <backups/worlds-*.tar.gz>"; exit 1; }
archive="$(realpath "$archive")"
cd "$(dirname "$0")/.."

# Read one KEY=value from .env without executing it (values may contain spaces).
env_get() { local v; v="$(grep -E "^$1=" .env | tail -n1 | cut -d= -f2-)"; v="${v%\"}"; v="${v#\"}"; echo "${v:-$2}"; }
DATA_DIR="$(env_get DATA_DIR ./data)"; BACKUP_DIR="$(env_get BACKUP_DIR ./backups)"
PUID="$(env_get PUID 1000)"; PGID="$(env_get PGID 1000)"
data_dir="$(realpath "${DATA_DIR:-./data}")"

tar -tzf "$archive" | grep -q '^worlds/' || { echo "not a worlds snapshot: $archive"; exit 1; }

read -r -p "Stop the server and restore $(basename "$archive")? [y/N] " ans
[[ "${ans,,}" == y* ]] || exit 1

# Stop both: the backup sidecar bind-mounts worlds/ and must re-mount the new dir.
docker compose stop valheim backup
if [[ -d "$data_dir/worlds" ]]; then
    keep="$data_dir/worlds.pre-restore-$(date +%Y%m%d-%H%M%S)"
    mv "$data_dir/worlds" "$keep"
    echo "Previous worlds moved to $keep"
fi
tar -xzf "$archive" -C "$data_dir"
docker compose start valheim backup
echo "Restored. Follow startup with: make logs"
