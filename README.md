# valheim-pi-server-docker

**A Valheim dedicated server for a Raspberry Pi 4, in Docker.** It's built for a small private server on a home network. Tested on a Pi 4 (8 GB) with 64-bit Raspberry Pi OS (Bookworm). Other 64-bit Linux distributions and ARM boards should work too ([what they need](docs/getting-started.md#other-distributions-and-boards)).

> **For your own setup:** the docs use the example address `192.168.1.50` and the folder `~/valheim-server` on the Pi. Use your Pi's address, and any folder you like.

Valheim's server only ships for x86_64, so this project runs it under emulation inside one self-contained arm64 container:

| Piece | Does |
|---|---|
| **DepotDownloader** (native arm64) | Installs and updates the server from Steam (app `896660`) at every start |
| **box64** | Runs `valheim_server.x86_64` on the Pi's arm64 CPU |
| **backup** sidecar (alpine) | Compressed snapshots of all worlds every few hours |
| **Makefile + scripts** | Every task as a `make` command: worlds, backups, players, status |

```
Pi 4 cores:  [0: left free for the host] [1 2 3: Valheim server + backups]
Host:        DATA_DIR   -> server files, worlds, player history  (mounted at /data)
             BACKUP_DIR -> snapshots and safety copies
Network:     UDP 2456-2457 on 192.168.1.50
```

## Expectations

- **Tested with two players** on a Pi 4. More may work: Valheim allows up to 10, but under emulation the CPU is the limit, so expect more lag with every extra player exploring or building. `make status` shows how close you are. Even with two, expect occasional lag during big fights, heavy building, or sailing into new areas.
- **The first start is slow:** 10-20 minutes while the server (~1 GB) downloads and the world is generated. Later starts take 2-3 minutes.
- **Emulation can be fragile.** A new box64 or Valheim release can break things; you can pin a known-good box64 ([Troubleshooting](docs/troubleshooting.md#the-server-crashes-after-someone-joins-or-after-a-few-hours)).
- **Crossplay (Xbox / Game Pass) is disabled:** it needs a library box64 can't emulate.
- **On a Pi 4, use a 5.1 V / 3 A power supply**, especially with a USB SSD ([why](docs/operations.md#power-and-throttling)).

## Quick start

On the Pi ([full guide](docs/getting-started.md)):

```bash
git clone https://github.com/seanBucholtz/valheim-pi-server-docker.git ~/valheim-server
cd ~/valheim-server
make setup        # creates .env, then stops
nano .env         # SERVER_NAME, WORLD_NAME, SERVER_PASSWORD, DATA_DIR/BACKUP_DIR (SSD), ADMIN_IDS
make setup        # checks Docker, user, folders; offers to raise swap to 2 GB
make build        # ~5-10 minutes
make up
make wait         # returns once the server is joinable
```

In Valheim: **Join Game → Join IP** → `192.168.1.50:2456`, then the password.

## Everyday commands

```bash
make status                      # healthy = joinable; CPU, memory, temperature, throttling
make players                     # who's on now, recent activity, every known player
make restart && make wait        # apply .env changes / update Valheim after a game update
make logs        make errors     # full log / real errors only
make backup      make backups    # snapshot now / list backups and free space

make worlds                      # worlds on the server (* = active)
make world-switch NAME=midgard   # switch to, or create, a world
make player NAME=Bjorn           # one player's history and Steam profile
make help                        # everything
```

Commands that stop the server or delete something ask first. Deleting or replacing a world makes you type its name, and a recovery copy is saved before anything is removed. Every command: [docs/commands.md](docs/commands.md).

## Documentation

| | |
|---|---|
| [Getting started](docs/getting-started.md) | Pi, SSD, memory limit, first start, connecting, other distributions and boards |
| [Commands](docs/commands.md) | Every `make` command |
| [Configuration](docs/configuration.md) | Every `.env` setting, and how to apply changes |
| [Worlds](docs/worlds.md) | New worlds, switching, deleting, import/export, seeds, restoring one world |
| [World settings](docs/world-settings.md) | Difficulty, death penalty, resources, raids, portals |
| [Players and admins](docs/players-and-admins.md) | Player history, Steam profiles, admins, console, cheats, bans |
| [Backups](docs/backups.md) | The backup layers, restoring, off-Pi copies |
| [Operations](docs/operations.md) | Monitoring, updates, power and throttling, performance, disk space |
| [Troubleshooting](docs/troubleshooting.md) | Connection problems, crashes, startup errors, harmless log messages |
| [How it works](docs/architecture.md) | Container internals, startup/shutdown, data layout, design decisions |

## License

[MIT](LICENSE). Valheim is a game by Iron Gate AB; this project only automates running its free dedicated server, and doesn't include it.

## Sources

- Box64 apt packages: [Pi-Apps-Coders/box64-debs](https://github.com/Pi-Apps-Coders/box64-debs)
- Steam downloader: [SteamRE/DepotDownloader](https://github.com/SteamRE/DepotDownloader)
- Admin cheats on dedicated servers: [JereKuusela/Server_devcommands](https://thunderstore.io/c/valheim/p/JereKuusela/Server_devcommands/), [valheim-dev](https://github.com/JereKuusela/valheim-dev)
- Valheim on a Pi (launch environment): [pimylifeup.com](https://pimylifeup.com/raspberry-pi-valheim-server/)
- Box64 stability notes for Valheim: [ptitSeb/box64#1182](https://github.com/ptitSeb/box64/issues/1182)
- World modifiers: [Connect Hosting](https://connecthosting.net/blog/valheim-world-modifiers-dedicated-server), [GameServerKings](https://www.gameserverkings.com/knowledge-base/valheim/valheim-world-modifiers/)
