#!/usr/bin/env bash
# Admin commands for the Valheim server. Run on the Pi through make (`make help`).
#
# World layout (current Valheim): DATA_DIR/worlds/worlds_local/<name>/ holds a
# world (_main.<N>.fwl2/.db2/.chunks/.ok plus *.chunk files), and Valheim's own
# backups are sibling folders <name>_backup_auto-<YYYYMMDD-HHMMSS>/.
#
# Destructive commands ask first: y/N for stops and restarts, and typing the
# world's name to delete or overwrite a world. There is deliberately no way to
# skip the prompt.
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/.."

# Read one KEY=value from .env without executing it (values may contain spaces).
env_get() {
    local v
    v="$(grep -E "^$1=" .env 2>/dev/null | tail -n1 | cut -d= -f2-)" || true
    v="${v%\"}"; v="${v#\"}"
    echo "${v:-$2}"
}
data_dir="$(realpath -m -- "$(env_get DATA_DIR ./data)")"
backup_dir="$(realpath -m -- "$(env_get BACKUP_DIR ./backups)")"
save_dir="$data_dir/worlds"
worlds_dir="$save_dir/worlds_local"
active_world="$(env_get WORLD_NAME '')"
stamp="$(date +%Y%m%d-%H%M%S)"

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# ------------------------------------------------------------ confirmation ----
need_tty() { [[ -t 0 ]] || die "this command asks for confirmation; run it in a terminal"; }
confirm() {         # <question>: y/N
    need_tty
    local ans; read -r -p "$1 [y/N] " ans
    [[ "${ans,,}" == y || "${ans,,}" == yes ]] || { echo "Cancelled."; exit 1; }
}
confirm_typed() {   # <word>: the user has to type it exactly
    need_tty
    local ans; read -r -p "Type '$1' to confirm (anything else cancels): " ans
    [[ "$ans" == "$1" ]] || { echo "Cancelled."; exit 1; }
}

# ------------------------------------------------------------------ helpers ----
check_name() {
    [[ -n "${1:-}" ]] || die "give a world name, e.g. NAME=midgard"
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] \
        || die "world names here may only use letters, digits, _ and - (got '$1')"
    [[ "$1" != *_backup_auto-* ]] || die "'$1' is one of Valheim's automatic backups, not a world"
}
is_world_dir() { local f=("$1"/_main.*.fwl2); (( ${#f[@]} )); }
world_exists() { [[ -d "$worlds_dir/$1" ]] && is_world_dir "$worlds_dir/$1"; }
auto_backups() { local d; for d in "$worlds_dir/$1"_backup_auto-*; do [[ -d "$d" ]] && echo "$d"; done; }
last_saved() {
    find "$1" -maxdepth 1 -name '_main.*' -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort | tail -n1
}
size_of() { du -shc -- "$@" 2>/dev/null | tail -n1 | cut -f1; }   # total of all paths

# Writing into the data folder as anyone but PUID would leave files the server can't use.
need_puid() {
    local puid; puid="$(env_get PUID 1000)"
    [[ "$(id -u)" == "$puid" ]] \
        || die "run this as the user with uid $puid (PUID in .env), not uid $(id -u)"
}

server_running() { [[ "$(docker inspect -f '{{.State.Running}}' valheim 2>/dev/null)" == true ]]; }
# Valheim logs "Connections N ZDOS:..." every few minutes; N = connected players.
players_now() {
    { docker compose logs --no-log-prefix --tail=2000 valheim 2>/dev/null \
        | grep -oE 'Connections [0-9]+ ZDOS' | tail -n1 | awk '{print $2}'; } || true
}
warn_players() {
    server_running || return 0
    local n; n="$(players_now)"
    if [[ -z "$n" ]]; then
        echo "Note: player count unknown (Valheim only logs it every few minutes). Check in game."
    elif (( n > 0 )); then
        echo "WARNING: $n player(s) connected. They'll be disconnected."
    fi
}
take_backup() {
    info "Taking a snapshot of all worlds first"
    mkdir -p "$backup_dir"
    docker compose run --rm --no-deps backup /bin/sh /scripts/backup-once.sh
}
# Wait until no file in <dir> changed for a minute (a save in progress), max ~10 min.
wait_quiet() {
    local tries=0
    while [[ -n "$(find "$1" -type f -mmin -1 2>/dev/null | head -n1)" ]]; do
        (( tries++ == 0 )) && echo "Waiting for the server to finish saving..."
        (( tries > 20 )) && { echo "Still changing after 10 min; packing anyway."; return 0; }
        sleep 30
    done
}
# Pack <names...> (folders in worlds_local) into <out>, checked before it's kept.
pack() {
    local out="$1"; shift
    mkdir -p "$backup_dir"
    tar -czf "$out.partial" -C "$worlds_dir" -- "$@"
    tar -tzf "$out.partial" >/dev/null || die "couldn't verify $out.partial"
    mv -- "$out.partial" "$out"
}
set_env() {         # <KEY> <value>: replace or add KEY in .env, keeping .env.bak
    [[ -f .env ]] || die ".env not found"
    cp -p .env .env.bak
    if grep -qE "^$1=" .env; then
        sed -i "s|^$1=.*|$1=$2|" .env
    else
        printf '%s=%s\n' "$1" "$2" >> .env
    fi
}

# ----------------------------------------------------------------- commands ----
cmd_worlds() {
    [[ -d "$worlds_dir" ]] || { echo "No worlds yet ($worlds_dir doesn't exist)."; return 0; }
    local d name n=0
    printf '  %-24s %8s  %-16s  %s\n' WORLD SIZE "LAST SAVED" "VALHEIM BACKUPS"
    for d in "$worlds_dir"/*/; do
        d="${d%/}"; name="${d##*/}"
        [[ "$name" == *_backup_auto-* ]] && continue
        is_world_dir "$d" || continue
        n=$((n + 1))
        printf '%s %-24s %8s  %-16s  %s\n' "$([[ "$name" == "$active_world" ]] && echo '*' || echo ' ')" \
            "$name" "$(size_of "$d")" "$(last_saved "$d")" "$(auto_backups "$name" | wc -l)"
    done
    (( n )) || echo "  (none)"
    echo
    if [[ -n "$active_world" ]] && ! world_exists "$active_world"; then
        echo "Active world '$active_world' (WORLD_NAME) doesn't exist yet: the server creates it on start."
    else
        echo "* = active world (WORLD_NAME in .env)"
    fi
    local old=("$worlds_dir"/*.fwl)
    (( ${#old[@]} )) && echo "Also found old-format world files (.fwl/.db): ${old[*]##*/}"
    return 0
}

cmd_world_switch() {
    local name="${1:-}"; check_name "$name"
    [[ "$name" != "$active_world" ]] || die "'$name' is already the active world"
    echo "Active world: '${active_world:-<none>}'  ->  new active world: '$name'"
    if world_exists "$name"; then
        echo "'$name' exists ($(size_of "$worlds_dir/$name"), last saved $(last_saved "$worlds_dir/$name"))."
    else
        echo "There's no world named '$name' yet: the server will CREATE it."
        echo "  - Generating a new world takes 10-20 minutes on the Pi."
        echo "  - The WORLD_* settings in .env (WORLD_PRESET etc.) apply to it. Check them first: make settings"
    fi
    warn_players
    echo "Steps: snapshot all worlds, set WORLD_NAME=$name in .env, restart the server"
    echo "(the current world is saved as the server stops)."
    confirm "Switch to '$name'?"
    take_backup
    set_env WORLD_NAME "$name"
    info "WORLD_NAME=$name (previous .env kept as .env.bak). Restarting the server"
    docker compose up -d --force-recreate valheim
    echo "Done. To know when it's joinable: make wait"
}

cmd_world_delete() {
    local name="${1:-}"; check_name "$name"; need_puid
    world_exists "$name" || die "no world named '$name' (see: make worlds)"
    [[ "$name" != "$active_world" ]] \
        || die "'$name' is the active world. Switch to another first: make world-switch NAME=<other>"
    local autos=() d; while IFS= read -r d; do autos+=("$d"); done < <(auto_backups "$name")
    local out="$backup_dir/deleted-$name-$stamp.tar.gz"
    echo "This permanently deletes world '$name' ($(size_of "$worlds_dir/$name" "${autos[@]}") with"
    echo "${#autos[@]} Valheim backup copies) from the server."
    echo "A recovery copy is saved first to: $out"
    echo "(Snapshots made before now still contain it too: make backups)"
    confirm_typed "$name"
    info "Saving the recovery copy"
    pack "$out" "$name" "${autos[@]##*/}"
    rm -rf -- "${worlds_dir:?}/$name" "${autos[@]}"
    echo "Deleted '$name'. To bring it back: make world-import FILE=$out"
}

cmd_world_export() {
    local name="${1:-}"; check_name "$name"
    world_exists "$name" || die "no world named '$name' (see: make worlds)"
    local out="$backup_dir/export-$name-$stamp.tar.gz"
    if [[ "$name" == "$active_world" ]] && server_running; then wait_quiet "$worlds_dir/$name"; fi
    pack "$out" "$name"
    echo "Exported '$name' ($(size_of "$out")) to $out"
    echo "It holds the world folder only (not Valheim's backup copies). Bring it back,"
    echo "or onto another server, with: make world-import FILE=$out"
}

cmd_world_import() {
    local src="${1:-}"; need_puid
    [[ -n "$src" ]] || die "give the export or world folder: FILE=<path>"
    [[ -e "$src" ]] || die "not found: $src"
    local tmp; tmp="$(mktemp -d "$save_dir/.import-XXXXXX")"
    # shellcheck disable=SC2064  # expand $tmp now
    trap "rm -rf -- '$tmp'" EXIT
    if [[ -d "$src" ]]; then
        is_world_dir "$src" || die "$src isn't a world folder (no _main.*.fwl2 inside)"
        cp -a -- "$(realpath -- "$src")" "$tmp/"
    else
        tar -xzf "$src" -C "$tmp" --no-same-owner || die "couldn't unpack $src (expected a .tar.gz)"
    fi
    # Exactly one world folder; *_backup_auto-* folders next to it come along.
    local d worlds=()
    for d in "$tmp"/*/; do
        d="${d%/}"
        [[ "${d##*/}" == *_backup_auto-* ]] && continue
        is_world_dir "$d" && worlds+=("${d##*/}")
    done
    (( ${#worlds[@]} == 1 )) \
        || die "expected exactly one world folder in $src, found ${#worlds[@]}: ${worlds[*]:-none}"
    local name="${worlds[0]}"; check_name "$name"
    local autos=("$tmp/$name"_backup_auto-*)

    echo "Importing world '$name' ($(size_of "$tmp/$name"), last saved $(last_saved "$tmp/$name"))"
    (( ${#autos[@]} )) && echo "with ${#autos[@]} Valheim backup copies."
    if world_exists "$name"; then
        if [[ "$name" == "$active_world" ]] && server_running; then
            die "'$name' is the active world and the server is running. Stop it first (make down), then import."
        fi
        local keep="$backup_dir/pre-import-$name-$stamp.tar.gz"
        echo "A world named '$name' already exists on the server and will be REPLACED."
        echo "Its current version is saved first to: $keep"
        confirm_typed "$name"
        info "Saving the current version"
        pack "$keep" "$name"
        rm -rf -- "${worlds_dir:?}/$name"
    else
        confirm "Import '$name'?"
    fi
    mkdir -p "$worlds_dir"
    mv -- "$tmp/$name" "$worlds_dir/$name"
    for d in "${autos[@]}"; do [[ -e "$worlds_dir/${d##*/}" ]] || mv -- "$d" "$worlds_dir/"; done
    echo "Imported '$name'."
    [[ "$name" == "$active_world" ]] || echo "To play it: make world-switch NAME=$name"
}

cmd_restore_world() {
    local file="${1:-}" name="${2:-}"; need_puid
    [[ -f "$file" ]] || die "give a snapshot: FILE=backups/worlds-....tar.gz (see: make backups)"
    check_name "$name"
    local in_snap
    in_snap="$(tar -tzf "$file" | sed -nE 's#^worlds/worlds_local/([^/]+)/_main\..*\.fwl2$#\1#p' \
               | grep -v '_backup_auto-' | sort -u)" || true
    grep -qxF -- "$name" <<<"$in_snap" \
        || die "$(basename "$file") has no world '$name'. Worlds in it: $(tr '\n' ' ' <<<"${in_snap:-none}")"

    local was_running=0 keep="$backup_dir/pre-restore-$name-$stamp.tar.gz"
    echo "Restore world '$name' from $(basename "$file"). Other worlds aren't touched."
    if [[ "$name" == "$active_world" ]] && server_running; then
        was_running=1
        echo "'$name' is the active world: the server is stopped for the restore and started again."
        warn_players
    fi
    if world_exists "$name"; then
        echo "The current '$name' is REPLACED. It's saved first to: $keep"
        confirm_typed "$name"
    else
        confirm "Restore '$name'?"
    fi
    local tmp; tmp="$(mktemp -d "$save_dir/.restore-XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf -- '$tmp'" EXIT
    tar -xzf "$file" -C "$tmp" --no-same-owner "worlds/worlds_local/$name"
    if (( was_running )); then info "Stopping the server (it saves first)"; docker compose stop valheim; fi
    if world_exists "$name"; then
        info "Saving the current version"; pack "$keep" "$name"
        rm -rf -- "${worlds_dir:?}/$name"
    fi
    mkdir -p "$worlds_dir"
    mv -- "$tmp/worlds/worlds_local/$name" "$worlds_dir/$name"
    if (( was_running )); then info "Starting the server"; docker compose start valheim; fi
    echo "Restored '$name'.$( (( was_running )) && echo ' To know when it is joinable: make wait')"
}

cmd_backups() {
    local files=("$backup_dir"/*.tar.gz) f
    if (( ${#files[@]} == 0 )); then echo "No backups yet in $backup_dir"; return 0; fi
    printf '%8s  %-16s  %s\n' SIZE DATE FILE
    for f in "${files[@]}"; do
        printf '%8s  %-16s  %s\n' "$(size_of "$f")" "$(date -r "$f" '+%F %H:%M')" "${f##*/}"
    done
    echo
    echo "Total: $(du -ch -- "${files[@]}" | tail -n1 | cut -f1) in ${#files[@]} files ($backup_dir)"
    df -h -- "$backup_dir" | awk 'NR == 2 { print "Free:  " $4 " of " $2 " on " $6 }'
    echo "worlds-*  snapshots (kept: newest BACKUP_KEEP)   deleted-*, pre-import-*, pre-restore-*  safety copies"
    echo "export-*  world exports.   Only worlds-* are pruned automatically."
}

cmd_backup_delete() {
    local file="${1:-}"
    [[ -f "$file" ]] || die "give a backup file: FILE=<path> (see: make backups)"
    [[ "$(dirname "$(realpath -- "$file")")" == "$backup_dir" && "$file" == *.tar.gz ]] \
        || die "only .tar.gz files directly in $backup_dir can be deleted here"
    echo "Delete $(basename "$file") ($(size_of "$file"), $(date -r "$file" '+%F %H:%M'))?"
    confirm "This can't be undone. Delete it?"
    rm -f -- "$file"
    echo "Deleted."
}

# Player events from the server log since the container started, as
# "<time> <event> <name> (<SteamID>)", then a last line "#online <ids...>".
#   Got handshake from client <id>         -> joined (connected from here)
#   Got character ZDOID from <name> : X:Y  -> spawned (first after joining); 0:0 = died;
#                                             a new ID after dying = respawned
#   Closing socket <id>                    -> left
# A name is matched to the SteamID of the most recent join that has no name yet.
player_events() {
    local raw
    raw="$( { docker compose logs --no-log-prefix valheim 2>/dev/null || true; } \
        | grep -E '\[entrypoint\] Starting |Got handshake from client|Got character ZDOID from|Closing socket|wrong password' \
        || true)"
    awk '
        function out(ev, who) { printf "%s  %-10s %s\n", t, ev, who }
        function label(id)    { return (id in nameof) ? nameof[id] " (" id ")" : id }
        { t = $2; sub(/[]:]+$/, "", t) }
        # Container logs survive a restart: everyone was disconnected when it stopped.
        /\[entrypoint\] Starting / {
            split("", on); split("", alive); split("", dead); pending = ""; started = 1
            out("started", "(server start)"); next
        }
        /Got handshake from client/ {
            id = $NF; on[id] = 1; out("joined", label(id))
            if (!(id in nameof)) pending = id   # a returning player keeps their name
            next
        }
        /Got character ZDOID from/ {
            s = $0; sub(/.*Got character ZDOID from /, "", s)
            zd = s; sub(/.* : /, "", zd); name = s; sub(/ : [^ ]*$/, "", name)
            if (zd == "0:0") { dead[name] = 1; out("died", name); next }
            if (!(name in alive)) {
                if (pending != "") { nameof[pending] = name; idof[name] = pending; pending = "" }
                alive[name] = 1; out("spawned", name (name in idof ? " (" idof[name] ")" : ""))
            } else if (name in dead) { delete dead[name]; out("respawned", name) }
            next
        }
        /Closing socket/ {
            id = $NF; out("left", label(id))
            delete on[id]; if (id in nameof) { delete alive[nameof[id]]; delete dead[nameof[id]] }
            if (pending == id) pending = ""
            next
        }
        /wrong password/ { s = $0; sub(/^[^ ]+ [^ ]+ /, "", s); out("refused", s " (wrong password)") }
        END {
            printf "#online%s ", (started ? "" : "?"); sep = ""
            for (id in on) { printf "%s%s", sep, label(id); sep = ", " }; print ""
        }' <<<"$raw"
}

cmd_players() {
    server_running || { echo "The server isn't running."; return 0; }
    local events online
    events="$(player_events)"
    online="$(tail -n1 <<<"$events")"; events="$(sed '$d' <<<"$events")"
    local sure=1; [[ "$online" == "#online?"* ]] && sure=0
    online="${online#\#online}"; online="${online#\?}"; online="${online# }"
    local count=0; [[ -n "$online" ]] && count="$(grep -oE '[0-9]{17}' <<<"$online" | wc -l)"
    echo "Connected now: $count${online:+  ->  $online}"
    if (( sure )); then
        echo "  (from joins and leaves since the server started; Valheim's own count, logged"
        echo "   every few minutes, says: $(players_now || true))"
    else
        echo "  WARNING: the log no longer reaches back to the server start, so this may be"
        echo "  incomplete. Valheim's own count (a few minutes old): $(players_now || true)"
    fi
    echo
    echo "Recent activity:"
    if [[ -n "$events" ]]; then tail -n 20 <<<"$events" | sed 's/^/  /'; else echo "  (nothing since the server started)"; fi
    echo
    local stats; stats="$(history_stats)"
    if [[ -z "$stats" ]]; then
        echo "Known players: no history yet ($players_log starts with the next server start)."
        return 0
    fi
    # Look up Steam names not cached yet (one request each, first time only).
    local id names first last sessions secs deaths worlds online missing=()
    while IFS=$'\t' read -r id _; do
        [[ "$id" =~ ^[0-9]{17}$ && -z "$(cached_steam_name "$id")" ]] && missing+=("$id")
    done <<<"$stats"
    if (( ${#missing[@]} )); then
        echo "(looking up ${#missing[@]} Steam name(s)...)"
        for id in "${missing[@]}"; do steam_info "$id" >/dev/null 2>&1 || true; done
    fi
    echo "Known players (since $(head -n1 "$players_log" | cut -f2 | cut -c1-10)); details: make player ID=<SteamID>"
    printf '  %-17s  %-16s  %-18s  %-16s  %8s  %6s\n' STEAMID "STEAM NAME" CHARACTERS "LAST SEEN" "PLAYED" DEATHS
    local steam
    while IFS=$'\t' read -r id names first last sessions secs deaths worlds online; do
        steam="$(cached_steam_name "$id")"
        printf '  %-17s  %-16.16s  %-18.18s  %-16s  %8s  %6s\n' "$id" "${steam:-?}" "${names//,/, }" \
            "$( (( online )) && echo 'online now' || echo "${last:0:16}")" "$(fmt_secs "$secs")" "$deaths"
    done < <(sort -t$'\t' -k4,4r <<<"$stats")
}

# ----------------------------------------------------------- player history ----
# DATA_DIR/players.log is written by the entrypoint (see player_event there).
# history_stats prints one tab-separated line per SteamID:
#   id  names(comma)  first  last  sessions  seconds  deaths  worlds(comma)  online(0/1)
# Sessions end at "leave", "stop", or a "start" without a stop before it (the last
# event before that start is used as the end then).
players_log="$data_dir/players.log"
# Steam display names for the `make players` table: SteamID, name, epoch looked up.
# Refreshed by every `make player`; new players are looked up once, failures
# ("?") retried after a day.
steam_cache="$data_dir/steam-names.tsv"
cached_steam_name() {   # <id>: prints the cached name, or nothing if missing or a failure to retry
    [[ -f "$steam_cache" ]] || return 0
    awk -F'\t' -v id="$1" -v now="$(date +%s)" \
        '$1 == id && !($2 == "?" && now - $3 > 86400) { print $2; exit }' "$steam_cache"
}
history_stats() {
    [[ -f "$players_log" ]] || return 0
    awk -F'\t' -v now="$(date +%s)" '
        function or(v) { return v == "" ? "-" : v }
        function close_all(at,   id) { for (id in on) { secs[id] += at - on[id]; delete on[id] } pending = "" }
        function addlist(arr, key, val) { if (index("," arr[key] ",", "," val ",") == 0) arr[key] = arr[key] (arr[key] == "" ? "" : ",") val }
        { t = $1 + 0; ts = $2; world = $3; ev = $4; a = $5; b = $6 }
        ev == "start" { close_all(running ? lastt : t); running = 1; lastt = t; next }
        ev == "stop"  { close_all(t); running = 0; lastt = t; next }
        ev == "join"  { if (!(a in first)) first[a] = ts; last[a] = ts; on[a] = t; sessions[a]++
                        addlist(worlds, a, world); pending = a; ids[a] = 1 }
        ev == "char"  { if (b == "0:0") { if (a in idof) deaths[idof[a]]++ }
                        else if (pending != "") { idof[a] = pending; addlist(names, pending, a); pending = "" }
                        if (a in idof) last[idof[a]] = ts }
        ev == "leave" { if (a in on) { secs[a] += t - on[a]; delete on[a] }; last[a] = ts; if (pending == a) pending = "" }
        { lastt = t }
        END {
            for (id in ids) {
                s = secs[id] + ((id in on) && running ? now - on[id] : 0)
                # "-" for empty fields: bash read would merge consecutive tabs.
                printf "%s\t%s\t%s\t%s\t%d\t%d\t%d\t%s\t%d\n", id, or(names[id]), or(first[id]), or(last[id]),
                    sessions[id], s, deaths[id], or(worlds[id]), ((id in on) && running) ? 1 : 0
            }
        }' "$players_log"
}
fmt_secs() { local s="$1"; printf '%dh %02dm' $((s / 3600)) $((s % 3600 / 60)); }

# ------------------------------------------------------------ Steam lookup ----
# Sends only the SteamID to Steam. Without STEAM_API_KEY: the public profile XML
# (no key needed). With it: the Web API, which also gives Valheim play time.
steam_info() {
    local id="$1" key; key="$(env_get STEAM_API_KEY '')"
    command -v python3 >/dev/null || { echo "  (Steam lookup needs python3)"; return 0; }
    command -v curl >/dev/null || { echo "  (Steam lookup needs curl)"; return 0; }
    local tmp; tmp="$(mktemp -d)"
    if [[ -n "$key" ]]; then
        curl -fsS -m 10 -o "$tmp/summary.json" \
            "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=$key&steamids=$id" 2>/dev/null || true
        curl -fsS -m 10 -o "$tmp/games.json" \
            "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=$key&steamid=$id&include_played_free_games=1&appids_filter%5B0%5D=892970" 2>/dev/null || true
    else
        curl -fsS -m 10 -A 'valheim-server-admin' -o "$tmp/profile.xml" \
            "https://steamcommunity.com/profiles/$id?xml=1" 2>/dev/null || true
    fi
    python3 -I - "$tmp" "$id" "$steam_cache" <<'PY' || echo "  (Steam lookup failed)"
import json, os, sys, time, xml.etree.ElementTree as ET
d, sid, cache = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
def add(label, value):
    if value not in (None, "", "0"):
        rows.append((label, str(value).strip()))
url = f"https://steamcommunity.com/profiles/{sid}"
p = os.path.join(d, "summary.json")
if os.path.exists(p):                       # Web API (STEAM_API_KEY)
    players = json.load(open(p)).get("response", {}).get("players", [])
    if players:
        s = players[0]
        states = ["offline", "online", "busy", "away", "snooze", "looking to trade", "looking to play"]
        st = states[s.get("personastate", 0)] if s.get("personastate", 0) < len(states) else "online"
        if s.get("gameextrainfo"):
            st += f", playing {s['gameextrainfo']}"
        add("Steam name", s.get("personaname"))
        add("Real name", s.get("realname"))
        add("Status", st)
        add("Profile", "public" if s.get("communityvisibilitystate") == 3 else "private / friends only")
        if s.get("timecreated"):
            add("Member since", time.strftime("%Y-%m-%d", time.localtime(s["timecreated"])))
        if s.get("lastlogoff"):
            add("Last Steam logoff", time.strftime("%Y-%m-%d %H:%M", time.localtime(s["lastlogoff"])))
        add("Country", s.get("loccountrycode"))
        url = s.get("profileurl") or url
    g = os.path.join(d, "games.json")
    if os.path.exists(g):
        games = json.load(open(g)).get("response", {}).get("games", [])
        if games:
            mins = games[0].get("playtime_forever", 0)
            add("Valheim total", f"{mins // 60}h {mins % 60:02d}m (all servers, from Steam)")
p = os.path.join(d, "profile.xml")
if os.path.exists(p):                       # public profile XML (no key)
    r = ET.parse(p).getroot()
    t = lambda k: (r.findtext(k) or "").strip()
    if r.tag == "profile":
        game = r.find("inGameInfo")
        state = t("stateMessage").replace("<br/>", " ")
        add("Steam name", t("steamID"))
        add("Real name", t("realname"))
        add("Status", state if not game else f"{state} ({game.findtext('gameName')})")
        add("Profile", t("privacyState").replace("friendsonly", "friends only"))
        add("Member since", t("memberSince"))
        add("Location", t("location"))
        add("Hours, 2 weeks", t("hoursPlayed2Wk"))
        if t("vacBanned") == "1":
            add("VAC", "banned")
        url = t("customURL") and f"https://steamcommunity.com/id/{t('customURL')}" or url
if not rows:
    print("  (Steam returned nothing: offline, private, or not a valid SteamID)")
for label, value in rows:
    print(f"  {label + ':':<17} {value}")
print(f"  {'Steam profile:':<17} {url}")

# Remember the display name for the `make players` table ("?" = lookup failed).
name = dict(rows).get("Steam name", "?").replace("\t", " ")
entries = {}
if os.path.exists(cache):
    for line in open(cache, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if len(f) == 3:
            entries[f[0]] = f
entries[sid] = [sid, name, str(int(time.time()))]
with open(cache + ".tmp", "w", encoding="utf-8") as out:
    for f in entries.values():
        out.write("\t".join(f) + "\n")
os.replace(cache + ".tmp", cache)
PY
    rm -rf -- "$tmp"
}

cmd_player() {
    local q="${1:-}" id=""
    [[ -n "$q" ]] || die "give a SteamID or character name: make player ID=7656... or NAME=Bjorn"
    local stats; stats="$(history_stats)"
    if [[ "$q" =~ ^[0-9]{17}$ ]]; then
        id="$q"
    else
        # Look the name up in the history (case-insensitive), then in the live log.
        id="$(awk -F'\t' -v q="${q,,}" '{ n = split($2, a, ","); for (i = 1; i <= n; i++) if (tolower(a[i]) == q) print $1 }' <<<"$stats" | head -n1)"
        if [[ -z "$id" ]]; then
            id="$(player_events | sed '$d' | awk -v q="${q,,}" '
                $2 == "spawned" { s = $0; sub(/^[^ ]+ +spawned +/, "", s)
                                  if (match(s, / \([0-9]+\)$/)) { nm = substr(s, 1, RSTART - 1); i = substr(s, RSTART + 2, 17)
                                                                  if (tolower(nm) == q) print i } }' | head -n1)"
        fi
        [[ -n "$id" ]] || die "no player called '$q' in the history or the current log (see: make players)"
    fi
    local row; row="$(awk -F'\t' -v id="$id" '$1 == id' <<<"$stats")"
    echo "SteamID $id"
    if [[ -n "$row" ]]; then
        local names first last sessions secs deaths worlds online
        IFS=$'\t' read -r _ names first last sessions secs deaths worlds online <<<"$row"
        echo "On this server (history since $(head -n1 "$players_log" | cut -f2 | cut -c1-10)):"
        printf '  %-17s %s\n' "Characters:" "${names//,/, }" "Status:" "$( (( online )) && echo 'online now' || echo offline)" \
            "First seen:" "$first" "Last seen:" "$last" "Sessions:" "$sessions" \
            "Play time:" "$(fmt_secs "$secs")" "Deaths:" "$deaths" "Worlds:" "${worlds//,/, }"
    elif [[ -f "$players_log" ]]; then
        echo "On this server: not in the player history yet."
    else
        echo "On this server: no player history yet (it starts with the next server start)."
    fi
    echo "From Steam:"
    steam_info "$id"
}

cmd_admins() {
    echo "ADMIN_IDS in .env: $(env_get ADMIN_IDS '(empty: adminlist.txt is managed by hand)')"
    local f
    for f in adminlist bannedlist permittedlist; do
        echo
        echo "$f.txt:"
        if [[ -f "$save_dir/$f.txt" ]]; then
            { grep -vE '^\s*(//|$)' "$save_dir/$f.txt" | sed 's/^/  /'; } || echo "  (empty)"
        else
            echo "  (no file)"
        fi
    done
    echo
    echo "permittedlist.txt empty = anyone with the password may join."
}

cmd_settings() {
    [[ -f .env ]] || die ".env not found"
    sed -E 's/^([A-Za-z0-9_]*(PASSWORD|SECRET|TOKEN|KEY)[A-Za-z0-9_]*=).*/\1<hidden>/I' .env
}

# Known harmless messages under box64 (see docs/troubleshooting.md).
NOISE='libpulse|libParty|libSDL3|AsyncResourceUpload failed|referenced script|Failed to place all|Signal (24|30)'
cmd_errors() {
    local n="${1:-5000}"
    [[ "$n" =~ ^[0-9]+$ ]] || die "LINES must be a number"
    { docker compose logs --no-log-prefix --tail="$n" valheim 2>/dev/null \
        | grep -iE 'exception|error|fatal|crash|segfault|segmentation|abort|out of memory|killed' \
        | grep -viE "$NOISE"; } \
        || echo "No errors in the last $n log lines (known harmless messages are hidden)."
}

cmd_clean_images() {
    docker system df
    echo
    local old; old="$(docker image ls --filter dangling=true --format '{{.ID}}  {{.CreatedSince}}  {{.Size}}')"
    if [[ -z "$old" ]]; then echo "No unused old images to remove."; return 0; fi
    echo "Unused old images (left behind by rebuilds):"
    sed 's/^/  /' <<<"$old"
    confirm "Remove them? (The current image and anything in use stay.)"
    docker image prune -f
}

usage() {
    sed -n 's/^    \([a-z-]*\)) .*## \(.*\)/  \1: \2/p' "$0"
    exit 1
}

cmd="${1:-}"; shift || true
case "$cmd" in
    worlds)        cmd_worlds ;;                    ## list worlds
    world-switch)  cmd_world_switch "$@" ;;         ## <name>: switch to / create a world
    world-delete)  cmd_world_delete "$@" ;;         ## <name>: delete a world (type its name)
    world-export)  cmd_world_export "$@" ;;         ## <name>: pack a world into BACKUP_DIR
    world-import)  cmd_world_import "$@" ;;         ## <file|folder>: add a world
    restore-world) cmd_restore_world "$@" ;;        ## <snapshot> <name>: restore one world
    backups)       cmd_backups ;;                   ## list backups, total, free space
    backup-delete) cmd_backup_delete "$@" ;;        ## <file>: delete one backup
    players)       cmd_players ;;                   ## connected now, recent activity, known players
    player)        cmd_player "$@" ;;               ## <SteamID|name>: history and Steam profile
    admins)        cmd_admins ;;                    ## admin, ban and permit lists
    settings)      cmd_settings ;;                  ## .env with the password hidden
    errors)        cmd_errors "$@" ;;               ## [lines]: server errors without noise
    clean-images)  cmd_clean_images ;;              ## remove unused old images
    *)             usage ;;
esac
