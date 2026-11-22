#!/usr/bin/env bash
# One-time preparation of the host (a 64-bit ARM machine, e.g. a Raspberry Pi 4).
# Run it on that machine from the project dir:
#   ./scripts/setup-host.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ok()   { echo "  [ok]   $*"; }
warn() { echo "  [warn] $*"; }
fail() { echo "  [FAIL] $*"; exit 1; }

echo "== Checking host =="
[[ "$(uname -m)" == "aarch64" ]] && ok "64-bit ARM kernel" || fail "needs aarch64, got $(uname -m)"
[[ "$(getconf PAGESIZE)" == "4096" ]] && ok "4K page size" \
    || warn "page size $(getconf PAGESIZE); box64 works best with 4K pages (on a Pi 5 set kernel=kernel8.img)"
if grep -qw memory /sys/fs/cgroup/cgroup.controllers 2>/dev/null || [[ -d /sys/fs/cgroup/memory ]]; then
    ok "memory cgroup enabled"
else
    warn "memory cgroup is off - MEMORY_LIMIT would be ignored (see docs/getting-started.md, step 5)"
fi
command -v docker >/dev/null && ok "$(docker --version)" || fail "Docker is not installed"
docker compose version >/dev/null 2>&1 && ok "docker compose available" || fail "docker compose plugin missing"
if docker info >/dev/null 2>&1; then ok "current user can talk to Docker"
else warn "run: sudo usermod -aG docker $USER  (then log out/in)"; fi

if command -v vcgencmd >/dev/null; then
    t="$(vcgencmd get_throttled)"
    [[ "$t" == "throttled=0x0" ]] && ok "no throttling ($t)" || warn "Pi reports $t - check PSU/cooling"
fi

echo "== Config =="
if [[ ! -f .env ]]; then
    cp .env.example .env
    chmod 600 .env
    warn "created .env from .env.example - edit it (at least SERVER_PASSWORD), then re-run this script"
    exit 0
fi
ok ".env exists"
# Read one KEY=value from .env without executing it (values may contain spaces).
env_get() { local v; v="$(grep -E "^$1=" .env | tail -n1 | cut -d= -f2-)"; v="${v%\"}"; v="${v#\"}"; echo "${v:-$2}"; }
DATA_DIR="$(env_get DATA_DIR ./data)"; BACKUP_DIR="$(env_get BACKUP_DIR ./backups)"
PUID="$(env_get PUID 1000)"; PGID="$(env_get PGID 1000)"
grep -q '^SERVER_PASSWORD=change-me-please$' .env && fail "set SERVER_PASSWORD in .env"

# The box64 build should match the board (see EMULATOR_BUILD in .env.example).
EMULATOR_BUILD="$(env_get EMULATOR_BUILD rpi4)"
model="$(tr -d '\0' 2>/dev/null </proc/device-tree/model || true)"
case "$EMULATOR_BUILD" in
    rpi4|rpi3|rk3399|tegrax1|generic) ;;
    *) fail "EMULATOR_BUILD=$EMULATOR_BUILD is not valid: use rpi4, rpi3, rk3399, tegrax1 or generic" ;;
esac
if [[ "$EMULATOR_BUILD" == rpi4 && -n "$model" && "$model" != *"Raspberry Pi 4"* && "$model" != *"Raspberry Pi 400"* && "$model" != *"Compute Module 4"* ]]; then
    warn "this is a '$model', but EMULATOR_BUILD=rpi4 - set rpi3, rk3399, tegrax1 or generic in .env"
else
    ok "EMULATOR_BUILD=$EMULATOR_BUILD${model:+ on $model}"
fi

[[ "${PUID:-1000}" == "$(id -u)" && "${PGID:-1000}" == "$(id -g)" ]] && ok "PUID/PGID match $(id -un)" \
    || warn "PUID/PGID (${PUID:-1000}:${PGID:-1000}) differ from you ($(id -u):$(id -g)) - fix .env or dir ownership"

echo "== Directories =="
# Pre-create worlds/ so Docker doesn't create the backup bind-mount as root.
for d in "${DATA_DIR:-./data}" "${DATA_DIR:-./data}/worlds" "${BACKUP_DIR:-./backups}"; do
    mkdir -p "$d"
    [[ -w "$d" ]] && ok "$d writable" || fail "$d is not writable by $(id -un)"
done
root_dev="$(findmnt -no SOURCE "$(df --output=target "${DATA_DIR:-./data}" | tail -n1)")"
[[ "$root_dev" == /dev/mmcblk* ]] && warn "DATA_DIR is on the SD card ($root_dev) - an SSD is recommended" \
    || ok "DATA_DIR is on $root_dev"

echo "== Swap =="
swap_mb=$(( $(awk '/SwapTotal/ {print $2}' /proc/meminfo) / 1024 ))
if (( swap_mb >= 2000 )); then
    ok "${swap_mb}MB swap"
elif [[ -f /etc/dphys-swapfile ]]; then
    warn "only ${swap_mb}MB swap"
    read -r -p "  Raise dphys-swapfile to 2048MB now? (uses sudo) [y/N] " ans
    if [[ "${ans,,}" == y* ]]; then
        sudo dphys-swapfile swapoff
        sudo sed -i -E 's/^#?CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
        sudo dphys-swapfile setup
        sudo dphys-swapfile swapon
        ok "swap is now $(( $(awk '/SwapTotal/ {print $2}' /proc/meminfo) / 1024 ))MB"
    fi
else
    warn "only ${swap_mb}MB swap and dphys-swapfile not found - add a 2GB swapfile (see docs/getting-started.md, Other distributions and boards)"
fi

echo
echo "Ready. Next: make build && make up && make wait"
