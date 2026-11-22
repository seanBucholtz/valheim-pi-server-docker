# Worlds

The server keeps every world it has ever loaded. One of them is **active**: the one named by `WORLD_NAME` in `.env`. The commands below manage the rest. For difficulty and other world rules, see [World settings](world-settings.md).

- [Seeing your worlds](#seeing-your-worlds)
- [Starting a new world](#starting-a-new-world)
- [Switching between worlds](#switching-between-worlds)
- [Deleting a world](#deleting-a-world)
- [Exporting and importing](#exporting-and-importing)
- [Bringing a world from your PC](#bringing-a-world-from-your-pc) (including seeds)
- [Taking a world to your PC](#taking-a-world-to-your-pc)
- [Restoring a world](#restoring-a-world)
- [How worlds are stored](#how-worlds-are-stored)
- [Safety copies](#safety-copies)

## Seeing your worlds

```
$ make worlds
  WORLD                        SIZE  LAST SAVED        VALHEIM BACKUPS
* midgard                       48M  2026-01-15 21:30  4

* = active world (WORLD_NAME in .env)
```

- **Size** counts the world folder only; Valheim's backup copies come on top.
- **Last saved** is the newest save generation. The world is saved every `SAVE_INTERVAL` (30 minutes by default) and on every clean stop.

## Starting a new world

```bash
nano .env                          # first: set the WORLD_* settings the new world should use
make world-switch NAME=vanaheim
make wait                          # generating a new world takes 10-20 minutes
```

`world-switch` sees that `vanaheim` doesn't exist yet and tells you it will be **created**. It then asks y/N, takes a snapshot of all worlds, sets `WORLD_NAME=vanaheim`, and restarts the server. The old world is saved as the server stops, and it stays on the server.

- **Names:** letters, digits, `_` and `-` only.
- **Seeds:** the server can't take one. See [Bringing a world from your PC](#bringing-a-world-from-your-pc).
- **World settings:** the `WORLD_*` values in `.env` apply to whichever world is active. If you've set a preset, the new world gets exactly what `.env` says.

## Switching between worlds

```bash
make world-switch NAME=midgard
make wait
```

This is the same command: for an existing world it just makes it active again. Each world keeps its own buildings, map exploration and boss progress. Characters live on each player's PC, so they can take their character between worlds.

## Deleting a world

```bash
make world-delete NAME=midgard
```

- **You can't delete the active world.** Switch to another one first.
- You have to **type the world's name** to confirm. Anything else cancels.
- Before deleting, it saves `BACKUP_DIR/deleted-midgard-<time>.tar.gz`, containing the world and Valheim's backup copies of it. The message tells you how to bring it back:
  ```bash
  make world-import FILE=backups/deleted-midgard-<time>.tar.gz
  ```
- Snapshots taken before the delete (`worlds-*.tar.gz`) also still contain the world until they're pruned.
- When you're sure you'll never want it back: `make backup-delete FILE=backups/deleted-midgard-<time>.tar.gz`.

## Exporting and importing

```bash
make world-export NAME=midgard                         # -> backups/export-midgard-<time>.tar.gz
make world-import FILE=backups/export-midgard-<time>.tar.gz
```

- **Export** packs the world folder only, without Valheim's backup copies. For the active world it waits for any save in progress to finish (up to 10 minutes).
- **Import** accepts:
  - an export;
  - a `deleted-*`, `pre-import-*` or `pre-restore-*` safety copy;
  - a plain **world folder** (one containing `_main.*.fwl2`).

  The file must hold exactly one world.
  - **New name:** asks y/N.
  - **Existing name:** you type the name, and the current version is saved as `pre-import-<world>-<time>.tar.gz` first.
  - **The active world while the server runs:** refused. The server would overwrite it at its next save. Run `make down` first, or switch away.
- After importing, play it with `make world-switch NAME=<world>`.

## Bringing a world from your PC

This is also how you use a particular **seed**:

1. In Valheim on your PC, **create** the world as a single-player world. Give it the seed you want, and a name made of letters, digits, `_` and `-`. **Load it once**, then quit.
2. Find its folder:
   - Windows: `%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\worlds_local\<name>`
   - Linux (Steam): `~/.config/unity3d/IronGate/Valheim/worlds_local/<name>`
3. Copy the folder to the Pi. For example with a USB stick, or `scp -r <name> <user>@192.168.1.50:~/`.
4. On the Pi:
   ```bash
   make world-import FILE=~/<name>
   make world-switch NAME=<name>
   make wait
   ```

The world's rules (difficulty and so on) come from the `WORLD_*` settings in `.env` when a preset is set, not from what you picked on the PC. A world saved in Steam Cloud needs to be moved to local storage in Valheim's world menu first.

## Taking a world to your PC

```bash
make world-export NAME=midgard
```

Copy `backups/export-midgard-<time>.tar.gz` to your PC and unpack it. Put the `midgard` folder into your `worlds_local` folder (above), and it shows up in Valheim's single-player world list.

## Restoring a world

To roll **one** world back to a snapshot, without touching the others:

```bash
make backups                                                    # pick a worlds-<time>.tar.gz
make restore-world FILE=backups/worlds-20260115-180000.tar.gz NAME=midgard
```

- It checks that the snapshot contains that world, and lists the worlds it does contain if not.
- The current version is saved as `pre-restore-midgard-<time>.tar.gz` first. Replacing it means typing the name.
- For the **active** world, the server is stopped (saving first), the world is restored, and the server is started again. Then run `make wait`.

To roll back **all** worlds at once: `make restore FILE=…` (see [Backups](backups.md#restoring)).

## How worlds are stored

```
DATA_DIR/worlds/worlds_local/
├── midgard/                               the world
│   ├── _main.12.fwl2   _main.12.db2       metadata and objects of save generation 12
│   ├── _main.12.chunks _main.12.ok        chunk index; .ok = that save finished
│   └── 20_20__1_10.chunk ...              map regions
├── midgard_backup_auto-20260115-210000/   Valheim's own backup copies (VALHEIM_BACKUPS)
└── ...
```

Each save writes a new generation (`_main.<N+1>.*`) and the `.ok` marker, then old generations are cleaned up. A copy taken mid-save could therefore be incomplete. That's why exports and snapshots wait until nothing has changed for a minute.

## Safety copies

| File in `BACKUP_DIR` | Made by | Contains |
|---|---|---|
| `deleted-<world>-<time>.tar.gz` | `world-delete` | The world and its Valheim backup copies |
| `pre-import-<world>-<time>.tar.gz` | `world-import` (when replacing) | The version that was replaced |
| `pre-restore-<world>-<time>.tar.gz` | `restore-world` (when replacing) | The version that was replaced |
| `export-<world>-<time>.tar.gz` | `world-export` | The world |

These are **never pruned automatically**. Check them now and then with `make backups`, and remove the ones you're done with using `make backup-delete`. They can all be brought back with `make world-import FILE=…`.
