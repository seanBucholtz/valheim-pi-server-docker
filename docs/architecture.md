# How it works

Valheim's dedicated server only exists for x86_64 PCs. A Raspberry Pi 4 is arm64. This project runs the x86_64 server under **emulation**, in a self-contained Docker container that downloads and updates the server by itself.

- [The pieces](#the-pieces)
- [What happens when the server starts](#what-happens-when-the-server-starts)
- [What happens when it stops](#what-happens-when-it-stops)
- [Health and readiness](#health-and-readiness)
- [Where everything lives](#where-everything-lives)
- [Design decisions](#design-decisions)
- [Repository layout](#repository-layout)

## The pieces

```
Raspberry Pi 4 (arm64, Raspberry Pi OS Bookworm; other 64-bit ARM hosts should work)
├── core 0 ───────────── left free, so the host stays responsive
└── cores 1-3 ─┬─ container "valheim"  (Debian bookworm-slim, arm64)
               │    tini ─> entrypoint.sh ─> box64 ─> valheim_server.x86_64
               │                     └─ DepotDownloader (native arm64): installs/updates the server
               └─ container "valheim-backup"  (alpine)
                    backup-loop.sh ─> backup-once.sh every BACKUP_INTERVAL_HOURS

Host folders (from .env):  DATA_DIR   -> /data in the server container
                           BACKUP_DIR -> /backups in the backup container
Network:                   UDP 2456-2457
```

| Piece | What it is | Why it's here |
|---|---|---|
| **box64** | An x86_64 → arm64 emulator with a dynamic recompiler. Installed from the Pi-Apps-Coders apt repository, in the build chosen by `EMULATOR_BUILD` (`box64-rpi4arm64` by default). | Runs `valheim_server.x86_64`. It maps the server's system-library calls onto native arm64 libraries, so only the game code itself is emulated. |
| **DepotDownloader** | A native arm64 .NET tool that downloads Steam content. A pinned version, checked against a SHA-256 checksum at build time. | Downloads and updates the Valheim server (Steam app `896660`) with an anonymous login. |
| **tini** | A minimal init process (PID 1). | Passes `docker stop`'s signal to the server and reaps zombie processes. |
| **entrypoint.sh** | The container's startup script. | Checks the config, writes the admin list, updates the server, builds the launch arguments, then becomes the server process. |
| **backup sidecar** | An alpine container that runs two small POSIX shell scripts. | Takes compressed snapshots of all worlds on a schedule, and prunes old ones. |
| **Makefile + scripts/** | Commands you run on the Pi. | Setup, start and stop, worlds, backups, players. See [Commands](commands.md). |

## What happens when the server starts

`docker/entrypoint.sh`, in order:

1. **Check the config.** These must be set: `SERVER_NAME`, `WORLD_NAME`, `SERVER_PASSWORD`. The password must be at least 5 characters and must not appear inside the server name. The world name must not contain a dot. These are Valheim's own rules, checked here so you get a clear message instead of a silent failure.
2. **World settings.** The `WORLD_*` settings are checked against the allowed values and turned into `-preset`, `-modifier` and `-setkey` arguments ([World settings](world-settings.md)). An invalid value stops the container with a list of valid ones.
3. **Folders.** Creates `/data/server`, `/data/worlds` and `/data/home`. It fails clearly if `/data` isn't writable by `PUID:PGID`.
4. **Admins.** If `ADMIN_IDS` is set, it rewrites `/data/worlds/adminlist.txt` from it ([Players and admins](players-and-admins.md)).
5. **Server download or update** (`UPDATE_ON_START=1`). Runs `DepotDownloader -app 896660 -os linux -osarch 64 -dir /data/server -validate`, up to 3 attempts. The `-os`/`-osarch` flags are needed, because otherwise it would pick files for the arm64 host. If every attempt fails but server files already exist, it starts the existing version with a warning.
6. **Player history.** Writes a `start` line to `/data/players.log`.
7. **Launch.** `exec box64 ./valheim_server.x86_64 -nographics -batchmode -name … -port 2456 -world … -password … -public … -savedir /data/worlds -saveinterval … -backups … -backupshort … -backuplong … <world settings> <EXTRA_SERVER_ARGS>`.
   - `exec` replaces the script with the server, so the server is the process that receives the stop signal.
   - The server's output passes through a small bash loop on its way to the container log. The loop:
     - creates `/tmp/valheim-ready` when the server logs `Game server connected` (see [Health and readiness](#health-and-readiness));
     - appends join, leave, character and death events to `/data/players.log`.

The Valheim server then loads (or, for a new name, **generates**) the world. That takes 2-3 minutes for an existing world, and 10-20 minutes to generate a new one on a Pi 4. It then connects to Steam and logs `Game server connected`.

## What happens when it stops

- `docker stop`, `make down`, `make restart` and a Pi shutdown all send **SIGINT** (`stop_signal` in compose). The server's response to SIGINT is to **save the world** and exit.
- Docker allows **120 seconds** for that (`stop_grace_period`) before it kills the server.
- The output loop sees the server's output end and writes a `stop` line to `players.log`.
- Valheim also saves on its own every `SAVE_INTERVAL` seconds (default 30 minutes).

Both containers use `restart: unless-stopped`. They come back after a crash or a Pi reboot, but **not** after `make down`, which removes them. Run `make up` to start them again.

## Health and readiness

The container's health check reports **healthy only when players can actually join**:

| Status | Meaning |
|---|---|
| `health: starting` | Downloading, loading or generating the world. Not joinable yet. |
| `healthy` | `/tmp/valheim-ready` exists (the server logged `Game server connected`) **and** the server process is running. |
| `unhealthy` | The server process is gone, or it wasn't ready within 30 minutes. |

The check runs every 30 seconds, so `healthy` appears within half a minute of the server being joinable. The flag is deleted on every start. `make wait` polls this status and returns when the server is joinable. `make status` shows it.

## Where everything lives

On the Pi, `DATA_DIR` (for example `/mnt/ssd/valheim/data`) is mounted at `/data` in the server container:

```
DATA_DIR/
├── server/                     Valheim server files (~1 GB, downloaded by DepotDownloader)
├── home/                       $HOME inside the container (Steam/Unity caches)
├── worlds/                     the -savedir
│   ├── worlds_local/
│   │   ├── <world>/            one folder per world:
│   │   │   ├── _main.<N>.fwl2    world metadata      ─┐
│   │   │   ├── _main.<N>.db2     world objects        ├ <N> = save generation
│   │   │   ├── _main.<N>.chunks  chunk index          │
│   │   │   ├── _main.<N>.ok      "save complete"     ─┘
│   │   │   └── *.chunk           map regions
│   │   └── <world>_backup_auto-<YYYYMMDD-HHMMSS>/   Valheim's own backup copies
│   ├── adminlist.txt           admins (managed from ADMIN_IDS when set)
│   ├── bannedlist.txt          banned SteamIDs
│   └── permittedlist.txt       if not empty: only these SteamIDs may join
├── players.log                 player history (written by the entrypoint)
└── steam-names.tsv             cached Steam display names (written by make players/player)

BACKUP_DIR/
├── worlds-<time>.tar.gz        scheduled/manual snapshots of all of worlds/ (pruned)
├── deleted-<world>-<time>.tar.gz, pre-import-…, pre-restore-…   safety copies (kept)
└── export-<world>-<time>.tar.gz                                  world exports (kept)
```

Current Valheim saves each world as a **folder** of files. Older guides talk about a `.fwl` and `.db` pair; that's the previous format.

## Design decisions

| Decision | Why |
|---|---|
| **DepotDownloader, not SteamCMD** | SteamCMD is 32-bit x86 and would need box86. Current `steamclient.so` needs a glibc function (`pthread_mutex_clocklock`) that box86 doesn't provide, so SteamCMD can't run on the Pi at all. DepotDownloader is native arm64. |
| **Self-contained container** | Nothing has to be downloaded on another machine. `scripts/fetch-server-x86.sh` exists only as a last resort. |
| **Crossplay disabled** | Crossplay needs `libSDL3`, which box64 can't wrap. Don't add `-crossplay`. |
| **Cores 1-3 only** (`SERVER_CPUS`) | Core 0 stays free, so the host stays responsive (SSH, a desktop, other services) even when the server is busy. |
| **SIGINT and a 120 s grace period** | SIGINT is how Valheim is told to save and quit. Anything that swallowed the signal would cost you up to `SAVE_INTERVAL` of progress. |
| **No `BOX64_*` project settings** | `.env` is passed into the container, and box64 reads **every** `BOX64_*` variable as one of its own options. A setting once called `BOX64_VERSION` made box64 print its version and exit with code 0, without starting the server. That's why the version pin is called `PIN_BOX64_VERSION`, and the build choice `EMULATOR_BUILD`. |
| **A bash read loop on the server output** | It drives readiness and player history without wrapping the server. Debian's `awk` (mawk) can't do this job: it reads pipes in large blocks, which would delay both the log and the flag. |
| **Memory limit = swap limit** (`mem_limit` = `memswap_limit`) | If the server runs away, it's restarted at `MEMORY_LIMIT`, instead of swapping to the SD card and slowing the whole Pi down. This needs the memory cgroup turned on ([Getting started](getting-started.md#5-turn-on-the-memory-limit)). |
| **Values checked in the entrypoint** | Valheim ignores invalid arguments silently, so typos in world settings would go unnoticed. |

## Repository layout

```
Dockerfile                  arm64 image: Debian + box64 + DepotDownloader; health check
docker-compose.yml          server + backup sidecar: CPU pinning, memory limit, ports, volumes, SIGINT
docker/entrypoint.sh        checks → admins → download/update → world settings → launch under box64
.env.example                every setting, documented (copy to .env on the Pi)
Makefile                    all commands (make help)
scripts/admin.sh            worlds, backups, players and admin commands behind make
scripts/setup-host.sh       one-time host checks, .env creation, swap, folders
scripts/restore.sh          restore all worlds from a snapshot
scripts/backup/             backup-loop.sh and backup-once.sh (busybox sh, run in the sidecar)
scripts/fetch-server-x86.sh last-resort server download on an x86 PC
docs/                       this documentation
```
