# Commands

Every command runs on the Pi from the project folder. `make help` lists them all.

**Confirmation levels:**
- 🟢 **No confirmation:** read-only, or safe.
- 🟡 **Asks y/N:** stops the server, or deletes a backup.
- 🔴 **You type the world's name:** deletes or replaces a world. A recovery copy is saved first.

Confirmations need a real terminal. A script can't answer them by piping input, and there's deliberately no flag to skip them.

- [Server](#server)
- [Status and logs](#status-and-logs)
- [Worlds](#worlds)
- [Backups](#backups)
- [Players and admins](#players-and-admins)
- [Maintenance](#maintenance)

## Server

| Command | | What it does |
|---|---|---|
| `make up` | 🟢 | Start the server and the backup sidecar (or apply changed host settings). |
| `make down` | 🟢 | Stop everything. The world is saved first. The containers are removed, so they won't start again after a reboot until `make up`. |
| `make restart` | 🟢 | Recreate and start the server: applies `.env` changes and updates Valheim (`UPDATE_ON_START=1`). Players are disconnected; check `make players` first. |
| `make wait` | 🟢 | Wait until the server is joinable, then print the address. Use it after `up`, `restart` or a world switch: `make restart && make wait`. Gives up after ~33 minutes, or as soon as the container stops or turns unhealthy. |
| `make build` | 🟢 | Build the image (pulls the latest Debian base). Needed after `Dockerfile` or `docker/entrypoint.sh` changes. |
| `make update` | 🟢 | Rebuild from scratch with the **latest box64**, then restart the server. If the new box64 misbehaves, see [Troubleshooting](troubleshooting.md#the-server-crashes-after-someone-joins-or-after-a-few-hours). |

## Status and logs

| Command | | What it does |
|---|---|---|
| `make status` | 🟢 | Containers and health (`starting` / `healthy` / `unhealthy`), CPU and memory use, Pi temperature and throttling. |
| `make logs` | 🟢 | Follow the server log (Ctrl-C stops following, not the server). |
| `make errors` | 🟢 | Only exceptions and errors from the server log, without the [known harmless messages](troubleshooting.md#harmless-messages-in-the-log). `make errors LINES=20000` looks further back (default 5000). |
| `make settings` | 🟢 | `.env` with passwords and keys hidden. Safe to share. |

## Worlds

See [Worlds](worlds.md) for the full guide.

| Command | | What it does |
|---|---|---|
| `make worlds` | 🟢 | List worlds: `*` marks the active one, plus size, last save and Valheim backup count. |
| `make world-switch NAME=<world>` | 🟡 | Make another world active, or **create** a new one with that name. Warns about connected players, takes a snapshot, sets `WORLD_NAME` in `.env` (old file kept as `.env.bak`), and restarts the server. |
| `make world-export NAME=<world>` | 🟢 | Pack one world into `BACKUP_DIR/export-<world>-<time>.tar.gz`. For the active world it waits until no save is in progress. |
| `make world-import FILE=<path>` | 🟡 / 🔴 | Add a world from an export, a recovery copy, or a world **folder** (e.g. copied from a PC). Replacing an existing world needs its name typed, and saves the old one as `pre-import-*` first. It refuses to replace the active world while the server runs. |
| `make world-delete NAME=<world>` | 🔴 | Delete a world and its Valheim backup copies. It saves `deleted-<world>-<time>.tar.gz` first, and refuses the active world. |
| `make restore-world FILE=<snapshot> NAME=<world>` | 🟡 / 🔴 | Restore **one** world from a snapshot. Other worlds aren't touched. The current version is saved as `pre-restore-*` first. For the active world, the server is stopped and started around the restore. |

## Backups

See [Backups](backups.md) for the full guide.

| Command | | What it does |
|---|---|---|
| `make backup` | 🟢 | Take a snapshot of all worlds right now (`worlds-<time>.tar.gz`). |
| `make backups` | 🟢 | List every backup file with size and date, plus the total and free space. |
| `make backup-delete FILE=<path>` | 🟡 | Delete one backup file. Only `.tar.gz` files directly in `BACKUP_DIR` are accepted. |
| `make restore FILE=<snapshot>` | 🟡 | Restore **all** worlds from a snapshot. The current `worlds/` folder is kept as `worlds.pre-restore-<time>`. Stops and restarts both containers. |

## Players and admins

See [Players and admins](players-and-admins.md) for the full guide.

| Command | | What it does |
|---|---|---|
| `make players` | 🟢 | Who's connected now (with character names), recent activity (joined, spawned, died, respawned, left, refused), and a table of **every known player**: Steam name, characters, last seen, play time, deaths. |
| `make player NAME="<character>"` or `ID=<SteamID>` | 🟢 | One player in detail: history on this server and their Steam profile. Sends only the SteamID to Steam. |
| `make admins` | 🟢 | `ADMIN_IDS`, plus the admin, ban and permit lists. |

## Maintenance

| Command | | What it does |
|---|---|---|
| `make setup` | 🟢 | One-time host checks: 64-bit OS, Docker, throttling, `.env`, PUID/PGID, folders, swap (offers to raise it to 2 GB, with sudo). |
| `make clean-images` | 🟡 | Remove unused old images left behind by rebuilds. Shows Docker's disk use first. |
| `make box-versions` | 🟢 | List box64 versions you can pin with `PIN_BOX64_VERSION` (for your `EMULATOR_BUILD`). |
| `make shell` | 🟢 | A shell inside the running server container (for debugging). |
