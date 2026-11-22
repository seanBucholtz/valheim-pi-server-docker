# Configuration (`.env`)

All settings live in `.env` in the project folder on the Pi. `make setup` creates it from `.env.example`, which documents every setting too. `.env` holds the server password, so don't copy it around or share it. **`make settings` prints it with secrets hidden**, which is safe to paste when asking for help.

- [How changes take effect](#how-changes-take-effect)
- [Server](#server)
- [World settings](#world-settings)
- [Admins and Steam](#admins-and-steam)
- [Host folders and user](#host-folders-and-user)
- [Resources](#resources)
- [Updates](#updates)
- [Valheim's saves and built-in backups](#valheims-saves-and-built-in-backups)
- [Snapshot backups](#snapshot-backups)
- [box64 tuning](#box64-tuning)
- [Rules for `.env`](#rules-for-env)

## How changes take effect

| Change | Apply with |
|---|---|
| Most settings (server, world, admins, updates, saves, box64 tuning) | `make restart` (recreates the server container so it reads `.env` again) |
| Host folders, user, CPU/memory limits, snapshot backup schedule | `make up` (recreates whichever containers changed) |
| `EMULATOR_BUILD`, `PIN_BOX64_VERSION` | `make build && make up` |
| `STEAM_API_KEY` | Nothing: used directly by `make player`/`make players` |

Every restart disconnects players, so check `make players` first.

## Server

| Setting | Default | What it does |
|---|---|---|
| `SERVER_NAME` | *(required)* | Name shown in game and in the server list. |
| `WORLD_NAME` | *(required)* | The active world. A name that doesn't exist yet is **created** at start. Letters, digits, `_` and `-`; no dots. Change it with `make world-switch NAME=…` ([Worlds](worlds.md)). |
| `SERVER_PASSWORD` | *(required)* | Join password. At least 5 characters, and it must not appear inside `SERVER_NAME` (Valheim's rule). |
| `SERVER_PUBLIC` | `0` | `1` lists the server in the in-game community server browser. Players outside your network also need UDP 2456-2457 forwarded on your router. `0` = join by IP only (recommended at home). |
| `EXTRA_SERVER_ARGS` | *(empty)* | Extra arguments for the server, added last. Split on spaces, with no quoting support. For difficulty, use the `WORLD_*` settings instead. |

## World settings

`WORLD_PRESET`, `WORLD_COMBAT`, `WORLD_DEATH_PENALTY`, `WORLD_RESOURCES`, `WORLD_RAIDS`, `WORLD_PORTALS`, and the on/off settings `WORLD_NO_BUILD_COST`, `WORLD_PLAYER_EVENTS`, `WORLD_PASSIVE_MOBS` and `WORLD_NO_MAP`. These are Valheim's world modifiers. They're **saved into the world**, so emptying a setting doesn't undo it. Every value and what it does: **[World settings](world-settings.md)**.

## Admins and Steam

| Setting | Default | What it does |
|---|---|---|
| `ADMIN_IDS` | *(empty)* | SteamID64s (17 digits, starting `7656119`), separated by spaces or commas. When set, `worlds/adminlist.txt` is rewritten from it at every start. When empty, the file is left alone, so you can edit it by hand. See [Players and admins](players-and-admins.md#admins-and-the-console). |
| `STEAM_API_KEY` | *(empty)* | Optional, free key from [steamcommunity.com/dev/apikey](https://steamcommunity.com/dev/apikey). `make player` then uses Steam's Web API, which also gives total Valheim hours. Without it, public profile pages are read instead. Hidden by `make settings`. |

## Host folders and user

| Setting | Default | What it does |
|---|---|---|
| `DATA_DIR` | `./data` | Host folder for server files, worlds, player history. Mounted at `/data`. Put it on the SSD, e.g. `/mnt/ssd/valheim/data`. |
| `BACKUP_DIR` | `./backups` | Host folder for snapshots and safety copies, e.g. `/mnt/ssd/valheim/backups`. |
| `PUID` / `PGID` | `1000` / `1000` | User and group the containers run as. Must own `DATA_DIR` and `BACKUP_DIR` (check with `id -u` / `id -g`). The admin commands also refuse to write as anyone else. |

## Resources

| Setting | Default | What it does |
|---|---|---|
| `SERVER_CPUS` | `1-3` | CPU cores for the server and backups. Core 0 is left free so the host stays responsive. `0-3` gives the server the whole CPU, if nothing else runs on the machine. On a board with more cores, use more (e.g. `1-7`). |
| `MEMORY_LIMIT` | `5g` | Memory cap for the server, which is also its swap cap. Hitting it restarts the server instead of swapping. Needs the memory cgroup ([Getting started](getting-started.md#5-turn-on-the-memory-limit)). The server uses about 1.5-2.5 GB with two players. |

## Updates

| Setting | Default | What it does |
|---|---|---|
| `UPDATE_ON_START` | `1` | `1` = download or update the server from Steam at every start, so `make restart` also updates Valheim. `0` = use the files already in `DATA_DIR/server` (for example after a manual download). |

## Valheim's saves and built-in backups

| Setting | Default | What it does |
|---|---|---|
| `SAVE_INTERVAL` | `1800` | Seconds between world saves. The world is also saved on every clean stop. |
| `VALHEIM_BACKUPS` | `4` | How many of Valheim's own backup copies to keep per world (`<world>_backup_auto-*` folders). `0` turns them off. |
| `VALHEIM_BACKUP_SHORT` | `7200` | Seconds until Valheim's first backups. |
| `VALHEIM_BACKUP_LONG` | `43200` | Seconds between later backups. |

## Snapshot backups

| Setting | Default | What it does |
|---|---|---|
| `BACKUP_INTERVAL_HOURS` | `6` | Hours between automatic snapshots of all worlds. The first one comes one interval after the sidecar starts. Use `make backup` for one right now. |
| `BACKUP_KEEP` | `28` | Snapshots (`worlds-*.tar.gz`) to keep. Older ones are pruned. 28 × 6 h ≈ one week. Safety copies and exports are never pruned. |

## box64 tuning

These reach box64 directly (it reads every `BOX64_*` variable). Values in `.env.example` are the ones reported to keep Valheim stable ([box64#1182](https://github.com/ptitSeb/box64/issues/1182)).

| Setting | In `.env.example` | What it does |
|---|---|---|
| `BOX64_DYNAREC_STRONGMEM` | `1` | How strictly x86 memory ordering is emulated: `0`-`3`. Higher is more stable and slower. Try `2`, then `3`, if the server crashes soon after someone joins. |
| `BOX64_DYNAREC_BIGBLOCK` | `0` | Size of recompiled code blocks. `0` is the safest. |
| `BOX64_DYNAREC_BLEEDING_EDGE` | `0` | Experimental optimisations off. |
| `BOX64_LOG` | `0` | box64's own logging. `1`+ is for debugging only (noisy, slower). |
| `EMULATOR_BUILD` | `rpi4` | Build-time: which box64 build to install, tuned for your CPU: `rpi4`, `rpi3`, `rk3399`, `tegrax1` or `generic` (Pi 5, RK3588 and anything else). A wrong value stops the build. See [Other distributions and boards](getting-started.md#other-distributions-and-boards). Apply with `make build && make up`. |
| `PIN_BOX64_VERSION` | *(empty)* | Build-time: pin an exact box64 apt version if a new build breaks Valheim. `make box-versions` lists them. Apply with `make build && make up`. |

Other `BOX64_*` debug variables work too, e.g. `BOX64_SHOWSEGV=1`, which prints every signal, including Mono's harmless `Signal 24/30`. Turn them back off afterwards.

## Rules for `.env`

- **Format:** one `KEY=value` per line, no spaces around `=`. Values may contain spaces (`SERVER_NAME=Our Valheim`), and need no quotes.
- **Never name your own setting `BOX64_…`.** box64 would treat it as one of its options. A setting once called `BOX64_VERSION` made the server exit silently at start.
- **Comments** start with `#` at the beginning of a line.
- **Missing settings** use their defaults, so an older `.env` keeps working after a project update. Compare it with `.env.example` to pick up new options.
