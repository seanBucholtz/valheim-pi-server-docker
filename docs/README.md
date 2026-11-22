# Documentation

| Guide | Read it when you want to… |
|---|---|
| **[Getting started](getting-started.md)** | Set up the Pi (or another ARM board), the SSD and the server from scratch, and join for the first time |
| **[Commands](commands.md)** | Look up any `make` command and what it asks before acting |
| **[Configuration](configuration.md)** | Know what every `.env` setting does, and how to apply a change |
| **[Worlds](worlds.md)** | Start a new world, switch, delete, export, import (including seeds from your PC), restore one world |
| **[World settings](world-settings.md)** | Change difficulty, death penalty, resources, raids, portals and other world rules |
| **[Players and admins](players-and-admins.md)** | See who plays (history, Steam profiles), become an admin, use the console and cheats, ban or allow-list players |
| **[Backups](backups.md)** | Understand the backup layers, restore, and keep copies off the Pi |
| **[Operations](operations.md)** | Check on the server, update Valheim and box64, handle power, throttling, performance and disk space |
| **[Troubleshooting](troubleshooting.md)** | Fix connection problems, crashes and startup errors, and tell real errors from harmless log noise |
| **[How it works](architecture.md)** | Understand the container, startup and shutdown, readiness, data layout and design decisions |

**Quick answers:**

| Question | Answer |
|---|---|
| Is it ready to join? | `make status` says `healthy`, or `make wait` returns |
| Who's on? | `make players` |
| The game updated and I can't join | `make restart && make wait` |
| I changed `.env` | `make restart` (some settings: `make up`, see [Configuration](configuration.md#how-changes-take-effect)) |
| New world | `make world-switch NAME=<name>`, then `make wait` |
| Something broke | `make errors`, then [Troubleshooting](troubleshooting.md) |
| Undo a world change | `make backups`, then `make restore-world FILE=… NAME=…` |
