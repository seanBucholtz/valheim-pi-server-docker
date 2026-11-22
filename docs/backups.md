# Backups

There are three layers of protection, from most frequent to most durable:

| Layer | What | Where | Kept |
|---|---|---|---|
| **1. Saves** | The world itself, saved every `SAVE_INTERVAL` (30 min) and on every clean stop | `DATA_DIR/worlds/worlds_local/<world>/` | Current only |
| **2. Valheim's backups** | Copies of each world that Valheim makes itself | `DATA_DIR/worlds/worlds_local/<world>_backup_auto-<time>/` | Newest `VALHEIM_BACKUPS` (4) |
| **3. Snapshots** | Compressed tarballs of **all** worlds plus the admin/ban lists | `BACKUP_DIR/worlds-<time>.tar.gz` | Newest `BACKUP_KEEP` (28) |

On top of that, the [world commands](worlds.md#safety-copies) save **safety copies** before deleting or replacing anything.

- [Snapshots](#snapshots)
- [Restoring](#restoring)
- [What's not backed up](#whats-not-backed-up)
- [Keeping backups somewhere else](#keeping-backups-somewhere-else)
- [Housekeeping](#housekeeping)

## Snapshots

- **Automatic:** the `valheim-backup` sidecar takes one every `BACKUP_INTERVAL_HOURS` (6). The first one comes one interval *after* the sidecar starts, not at start.
- **Manual:** `make backup`, for example before experimenting with cheats, world settings or a mod. `make world-switch` takes one automatically.
- **Safe timing:** before writing, the snapshot waits until no world file has changed for a minute, so it never catches a save half-written. It waits up to 10 minutes, then takes the snapshot anyway. It's written as `.partial` and only renamed when complete.
- **Pruning:** only the newest `BACKUP_KEEP` files matching `worlds-*.tar.gz` are kept. 28 × 6 h ≈ one week of history. Nothing else in `BACKUP_DIR` is ever pruned.
- **Size:** each snapshot holds every world, including Valheim's backup copies inside `worlds/`, so it's several times one world's size. Check with `make backups`.

```
$ make backups
    SIZE  DATE              FILE
     85M  2026-01-15 12:00  worlds-20260115-120000.tar.gz
     85M  2026-01-15 18:00  worlds-20260115-180000.tar.gz

Total: 170M in 2 files (/mnt/ssd/valheim/backups)
Free:  180G of 230G on /mnt/ssd
```

## Restoring

| You want to… | Command |
|---|---|
| Roll back **one** world | `make restore-world FILE=backups/worlds-<time>.tar.gz NAME=<world>` ([details](worlds.md#restoring-a-world)) |
| Roll back **everything** (all worlds and the admin/ban/permit lists) | `make restore FILE=backups/worlds-<time>.tar.gz` |
| Undo a world delete, import or restore | `make world-import FILE=backups/deleted-…` (or `pre-import-…`, `pre-restore-…`) |
| Use one of Valheim's own backup copies | See below |

**`make restore`** (everything) asks y/N, stops both containers, moves the current `worlds/` folder aside to `worlds.pre-restore-<time>` (nothing is deleted), unpacks the snapshot, and starts both containers again. Remove the `worlds.pre-restore-*` folder yourself once you're happy.

**From a Valheim backup copy** (`<world>_backup_auto-<time>/`):

```bash
make down
cd /mnt/ssd/valheim/data/worlds/worlds_local        # your DATA_DIR/worlds/worlds_local
mv midgard midgard.broken
cp -a midgard_backup_auto-20260115-210000 midgard
cd ~/valheim-server && make up && make wait
```

## What's not backed up

Snapshots cover `DATA_DIR/worlds/` only. Not included:

| Not included | Why that's fine |
|---|---|
| `DATA_DIR/server/` | Re-downloaded automatically. |
| `DATA_DIR/players.log`, `steam-names.tsv` | Player history. Copy it yourself if you care about it. |
| `.env` | Keep your own copy somewhere private: it holds the password. |
| **Characters** | They live on each player's PC, not on the server. Each player backs up their own. |

## Keeping backups somewhere else

Snapshots on the same disk as the world protect you from mistakes and bad saves, **not from the disk failing**. `BACKUP_DIR` is a plain folder of self-contained tarballs, so copying it anywhere works.

**Pull from another machine** (the Pi then holds no credentials for it). On that machine:

```bash
# crontab -e
15 */6 * * *  rsync -a <user>@192.168.1.50:/mnt/ssd/valheim/backups/ /srv/backups/valheim/
```

**Or copy to your PC now and then:** `scp <user>@192.168.1.50:/mnt/ssd/valheim/backups/worlds-<time>.tar.gz .`

## Housekeeping

- Check space with `make backups`. It shows the total and free space.
- Delete safety copies and exports you no longer need with `make backup-delete FILE=…` (asks y/N).
- To keep more history, raise `BACKUP_KEEP`. To take snapshots more often, lower `BACKUP_INTERVAL_HOURS`. Apply either with `make up`.
- If space is short, `VALHEIM_BACKUPS=2` halves Valheim's own copies, which also makes every snapshot smaller.
