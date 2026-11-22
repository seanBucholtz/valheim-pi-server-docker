#!/usr/bin/env bash
# Installs/updates the Valheim server with DepotDownloader (native arm64), then
# launches it under box64. Runs as the unprivileged PUID:PGID user.
set -euo pipefail

VALHEIM_APP_ID=896660
DATA=/data
SERVER_DIR="$DATA/server"
SAVE_DIR="$DATA/worlds"
export HOME="$DATA/home"

log() { echo "[$(date '+%F %T')] [entrypoint] $*"; }
die() { log "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------- config ----
: "${SERVER_NAME:?SERVER_NAME must be set in .env}"
: "${WORLD_NAME:?WORLD_NAME must be set in .env}"
: "${SERVER_PASSWORD:?SERVER_PASSWORD must be set in .env}"
SERVER_PUBLIC="${SERVER_PUBLIC:-0}"
UPDATE_ON_START="${UPDATE_ON_START:-1}"
SAVE_INTERVAL="${SAVE_INTERVAL:-1800}"
VALHEIM_BACKUPS="${VALHEIM_BACKUPS:-4}"
VALHEIM_BACKUP_SHORT="${VALHEIM_BACKUP_SHORT:-7200}"
VALHEIM_BACKUP_LONG="${VALHEIM_BACKUP_LONG:-43200}"

# Valheim refuses to start with a short password, or one contained in the name.
(( ${#SERVER_PASSWORD} >= 5 )) || die "SERVER_PASSWORD must be at least 5 characters"
[[ "${SERVER_NAME,,}" != *"${SERVER_PASSWORD,,}"* ]] \
    || die "SERVER_PASSWORD must not appear inside SERVER_NAME"
[[ "$WORLD_NAME" != *.* ]] || die "WORLD_NAME must not contain a file extension / dot"

# -------------------------------------------------------- world settings ----
# WORLD_* in .env -> -preset / -modifier / -setkey (docs/world-settings.md).
# Empty = don't pass it. Values are checked here, because the server silently
# ignores ones it doesn't know. Order matters: a preset overwrites earlier
# modifiers, so it goes first.
world_args=()
world_value=""
# world_check <SETTING> <allowed...>: false if SETTING is empty; otherwise puts the
# lower-cased value in world_value, or stops with an error if it isn't allowed.
world_check() {
    local name="$1"; shift
    world_value="${!name:-}"; world_value="${world_value,,}"
    [[ -n "$world_value" ]] || return 1
    [[ "$world_value" =~ ^[a-z]+$ && " $* " == *" $world_value "* ]] \
        || die "$name='${!name}' is not valid. Use one of: $* (or leave it empty)"
}
add_modifier() {    # <SETTING> <modifier key> <allowed values except normal...>
    local name="$1" key="$2"; shift 2
    world_check "$name" normal "$@" || return 0
    # The server has no "normal" value; normal is simply not passing the modifier.
    [[ "$world_value" == normal ]] || world_args+=(-modifier "$key" "$world_value")
}
add_key() {         # <SETTING> <global key>: 1 = set it, 0/empty = don't
    case "${!1:-0}" in
        1) world_args+=(-setkey "$2") ;;
        0) ;;
        *) die "$1='${!1}' is not valid. Use 1 (on) or 0 (off)" ;;
    esac
}

if world_check WORLD_PRESET normal casual easy hard hardcore immersive hammer; then
    world_args+=(-preset "$world_value")
fi
add_modifier WORLD_COMBAT        combat       veryeasy easy hard veryhard
add_modifier WORLD_DEATH_PENALTY deathpenalty casual veryeasy easy hard hardcore
add_modifier WORLD_RESOURCES     resources    muchless less more muchmore most
add_modifier WORLD_RAIDS         raids        none muchless less more muchmore
add_modifier WORLD_PORTALS       portals      casual hard veryhard
add_key WORLD_NO_BUILD_COST  nobuildcost
add_key WORLD_PLAYER_EVENTS  playerevents
add_key WORLD_PASSIVE_MOBS   passivemobs
add_key WORLD_NO_MAP         nomap

mkdir -p "$SERVER_DIR" "$SAVE_DIR" "$HOME" \
    || die "cannot write to /data - check DATA_DIR ownership matches PUID/PGID"

# ---------------------------------------------------------------- admins ----
# ADMIN_IDS (SteamID64s, space/comma separated) -> adminlist.txt in the save dir.
# Admins can use `devcommands` in the F5 console. Empty = leave the file alone,
# so hand edits to adminlist.txt still work.
if [[ -n "${ADMIN_IDS:-}" ]]; then
    {
        echo "// Managed by the container from ADMIN_IDS in .env - edits here are overwritten."
        for id in ${ADMIN_IDS//,/ }; do
            id="${id#Steam_}"
            if [[ "$id" =~ ^[0-9]{17}$ ]]; then
                # Valheim matches platform-prefixed IDs; keep the bare form too.
                echo "Steam_$id"
                echo "$id"
            else
                log "WARNING: ignoring ADMIN_IDS entry '$id' (expected a 17-digit SteamID64)" >&2
            fi
        done
    } > "$SAVE_DIR/adminlist.txt"
    log "Admins: $(grep -c '^Steam_' "$SAVE_DIR/adminlist.txt" || true) from ADMIN_IDS."
fi

# ------------------------------------------------------- server download ----
# DepotDownloader runs natively on arm64 and logs in to Steam anonymously.
# -os/-osarch are required: by default it would pick depots for the host (arm64).
update_server() {
    for attempt in 1 2 3; do
        log "Installing/updating Valheim server with DepotDownloader (attempt $attempt)..."
        if DepotDownloader -app "$VALHEIM_APP_ID" -os linux -osarch 64 \
                           -dir "$SERVER_DIR" -validate \
           && [[ -f "$SERVER_DIR/valheim_server.x86_64" ]]; then
            # Not every release preserves the executable bit; make sure.
            chmod +x "$SERVER_DIR/valheim_server.x86_64"
            log "Server files are up to date."
            return 0
        fi
        sleep 10
    done
    return 1
}

if [[ "$UPDATE_ON_START" == "1" ]]; then
    if ! update_server; then
        [[ -f "$SERVER_DIR/valheim_server.x86_64" ]] \
            || die "Server download failed and no server files exist. See README: 'Server download fails'."
        log "WARNING: update failed; starting the existing server files."
    fi
else
    log "UPDATE_ON_START=0, skipping server update."
fi

[[ -f "$SERVER_DIR/valheim_server.x86_64" ]] \
    || die "No server at $SERVER_DIR/valheim_server.x86_64 (set UPDATE_ON_START=1 or copy files in)."

# ---------------------------------------------------------------- launch ----
# box64 reads every BOX64_* variable as an option; BOX64_VERSION (the old name
# of PIN_BOX64_VERSION in .env) makes it print its version and exit 0.
if [[ -v BOX64_VERSION ]]; then
    log "WARNING: ignoring BOX64_VERSION from .env - rename it to PIN_BOX64_VERSION."
    unset BOX64_VERSION
fi
cd "$SERVER_DIR"
export LD_LIBRARY_PATH="$SERVER_DIR/linux64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export SteamAppId=892970

args=(
    -nographics -batchmode
    -name "$SERVER_NAME"
    -port 2456
    -world "$WORLD_NAME"
    -password "$SERVER_PASSWORD"
    -public "$SERVER_PUBLIC"
    -savedir "$SAVE_DIR"
    -saveinterval "$SAVE_INTERVAL"
    -backups "$VALHEIM_BACKUPS"
    -backupshort "$VALHEIM_BACKUP_SHORT"
    -backuplong "$VALHEIM_BACKUP_LONG"
    "${world_args[@]}"
)
# Crossplay is intentionally NOT enabled: it needs libSDL3, which box64 can't wrap.
# EXTRA_SERVER_ARGS comes last, after any WORLD_PRESET, so a preset can't undo it.
if [[ -n "${EXTRA_SERVER_ARGS:-}" ]]; then
    read -r -a extra <<< "$EXTRA_SERVER_ARGS"
    args+=("${extra[@]}")
fi

log "Starting '$SERVER_NAME' world '$WORLD_NAME' (public=$SERVER_PUBLIC) under $(box64 --version 2>&1 | head -n1)"
if (( ${#world_args[@]} )); then
    log "World settings: ${world_args[*]}"
else
    log "World settings: none set in .env (the world keeps whatever it has saved)"
fi
log "BOX64 tuning: STRONGMEM=${BOX64_DYNAREC_STRONGMEM:-unset} BIGBLOCK=${BOX64_DYNAREC_BIGBLOCK:-unset} BLEEDING_EDGE=${BOX64_DYNAREC_BLEEDING_EDGE:-unset}"
# Readiness for the HEALTHCHECK: the server's output passes through a read loop
# unchanged, which creates READY_FLAG when the server logs "Game server connected"
# (joinable). Cleared on every start, because /tmp survives `docker compose restart`.
# A bash loop, not awk: Debian's mawk reads pipes in blocks, which would delay
# both the flag and the container log.
READY_FLAG=/tmp/valheim-ready
rm -f "$READY_FLAG"

# Player history: the same loop appends join/leave/death events to DATA/players.log,
# which survives restarts, rebuilds and log rotation (read by `make players/player`).
# Tab-separated: epoch, local time, world, event, arg1, arg2
#   start <world> | stop | join <steamid> | char <name> <zdoid> (0:0 = died)
#   leave <steamid> | refused <steamid> (wrong password)
PLAYERS_LOG="$DATA/players.log"
player_event() {
    printf '%(%s)T\t%(%F %T)T\t%s\t%s\t%s\t%s\n' -1 -1 "$WORLD_NAME" "$1" "${2:-}" "${3:-}" \
        >> "$PLAYERS_LOG" 2>/dev/null || true
}
re_join='Got handshake from client ([0-9]+)'
re_char='Got character ZDOID from (.+) : (-?[0-9]+:-?[0-9]+)'
re_leave='Closing socket ([0-9]+)'
re_id='([0-9]{17})'

mark_ready() {
    local line ready=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line"
        if (( ! ready )) && [[ "$line" == *"Game server connected"* ]]; then
            : > "$READY_FLAG"; ready=1
        fi
        # Cheap substring checks first; the regex only runs on candidate lines.
        case "$line" in
            *"Got handshake from client"*) [[ "$line" =~ $re_join ]] && player_event join "${BASH_REMATCH[1]}" ;;
            *"Got character ZDOID from"*)  [[ "$line" =~ $re_char ]] && player_event char "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" ;;
            *"Closing socket"*)            [[ "$line" =~ $re_leave ]] && player_event leave "${BASH_REMATCH[1]}" ;;
            *"wrong password"*)            [[ "$line" =~ $re_id ]] && player_event refused "${BASH_REMATCH[1]}" ;;
        esac
    done
    player_event stop   # the server's output ended: it stopped, and everyone is disconnected
}
player_event start "$WORLD_NAME"
# exec so SIGINT from `docker stop` reaches the server and it saves the world.
# tini signals only the server, not the loop; the loop ends with the server's output.
exec box64 ./valheim_server.x86_64 "${args[@]}" > >(mark_ready) 2>&1
