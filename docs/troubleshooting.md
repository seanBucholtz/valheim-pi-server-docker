# Troubleshooting

Start with `make status` (is it running, is it healthy?) and `make errors` (real errors only). `make logs` shows everything.

- [Can't connect](#cant-connect)
- [The container stops or keeps restarting](#the-container-stops-or-keeps-restarting)
- [The server exits right after starting, with no error](#the-server-exits-right-after-starting-with-no-error)
- [The server download fails](#the-server-download-fails)
- [Stuck at "health: starting"](#stuck-at-health-starting)
- [The server crashes after someone joins, or after a few hours](#the-server-crashes-after-someone-joins-or-after-a-few-hours)
- [Admin and console problems](#admin-and-console-problems)
- [World settings didn't apply](#world-settings-didnt-apply)
- [A `.env` change had no effect](#a-env-change-had-no-effect)
- [Memory limit ignored](#memory-limit-ignored)
- [Under-voltage or throttling](#under-voltage-or-throttling)
- [Permission denied](#permission-denied)
- [Admin command errors](#admin-command-errors)
- [Harmless messages in the log](#harmless-messages-in-the-log)
- [Digging deeper](#digging-deeper)

## Can't connect

| Symptom | Cause and fix |
|---|---|
| "Failed to connect" right after a start | The server isn't ready yet. Run `make wait`, or wait for `make status` to say `healthy`. A new world takes 10-20 minutes. |
| "Incompatible version" / version mismatch | The game updated but the server didn't. Run `make restart && make wait`. If Steam hasn't published the server update yet, wait a little and try again. |
| "Incorrect password" | Check `SERVER_PASSWORD` (`make settings` hides it, so look in `.env` on the Pi). Failed attempts show up as `refused` in `make players`. |
| Nothing happens, from inside your network | Check the address is `192.168.1.50:2456`, the Pi still has that address (`hostname -I`), and the container's ports are listed in `make status`. A firewall on the Pi (`sudo ufw status`) must allow UDP 2456-2457. |
| Works at home, not from outside | Set `SERVER_PUBLIC=1` and forward UDP 2456-2457 on your router to the Pi. Xbox/Game Pass players can't join (crossplay is disabled). |

## The container stops or keeps restarting

Run `make logs`. The entrypoint stops with a clear message for each of these:

| Message | Fix |
|---|---|
| `SERVER_NAME must be set in .env` (also `WORLD_NAME`, `SERVER_PASSWORD`) | Set it in `.env`. |
| `SERVER_PASSWORD must be at least 5 characters` | Use a longer password. |
| `SERVER_PASSWORD must not appear inside SERVER_NAME` | Valheim's rule; change one of them. |
| `WORLD_NAME must not contain a file extension / dot` | Remove the dot. |
| `WORLD_COMBAT='superhard' is not valid. Use one of: …` (any `WORLD_*`) | Use one of the listed values. See [World settings](world-settings.md). |
| `cannot write to /data - check DATA_DIR ownership matches PUID/PGID` | See [Permission denied](#permission-denied). |
| `Server download failed and no server files exist` | See [The server download fails](#the-server-download-fails). |
| No message, but `docker inspect valheim --format '{{.State.OOMKilled}}'` says `true` | The server hit `MEMORY_LIMIT`. Raise it a little, and check for a growing world or a box64 problem. |

## The server exits right after starting, with no error

If the log shows only box64's banner (`Box64 arm64 v0.4.x ...`) and the container exits with code 0 a second or two later, **a `BOX64_*` setting in `.env` is the usual cause**. box64 reads every `BOX64_*` environment variable as one of its options, and `.env` is passed into the container. `BOX64_VERSION` in particular makes box64 print its version and exit.

- Rename or remove the variable. The version pin is called `PIN_BOX64_VERSION`. Then run `make restart`.
- The entrypoint now removes `BOX64_VERSION` itself, with a warning, but any other unexpected `BOX64_*` setting can still change box64's behaviour.

## The server download fails

The container downloads the server with [DepotDownloader](https://github.com/SteamRE/DepotDownloader) (anonymous Steam login, native arm64) and tries 3 times per start. If it fails but older server files exist, it starts those with a warning.

1. Check the Pi has internet access: `curl -sI https://steamcommunity.com | head -1`.
2. Try again later: Steam has outages.
3. Try a newer DepotDownloader: set `DEPOTDOWNLOADER_VERSION` and `DEPOTDOWNLOADER_SHA256` (from the release's `DepotDownloader-linux-arm64.zip`) in `Dockerfile`, then `make build && make up`.
4. **Last resort**, on an x86 PC with Docker: `./scripts/fetch-server-x86.sh ./valheim-server-files`. Copy the result into `DATA_DIR/server/` on the Pi, set `UPDATE_ON_START=0`, and run `make restart`. You'll have to repeat that for every update.

SteamCMD isn't used and can't be: it's 32-bit x86, and its `steamclient.so` needs `pthread_mutex_clocklock`, which box86 doesn't provide.

## Stuck at "health: starting"

`make logs` shows how far it got:

| Last thing in the log | Meaning |
|---|---|
| DepotDownloader progress | Still downloading (~1 GB on the first start). |
| `Failed to place all …`, lots of zone/location lines | **Generating a new world**: 10-20 minutes. Normal. |
| `Loading: Done` but no `Game server connected` | Connecting to Steam. If it stays that way for over 5 minutes, check internet access. |
| Nothing for a long time, CPU at 0 | Hung. Run `make restart`. |

After 30 minutes without becoming ready, the status turns `unhealthy`.

## The server crashes after someone joins, or after a few hours

This is a known box64 + Unity/Mono problem ([box64#1182](https://github.com/ptitSeb/box64/issues/1182)). Work through these in order, with `make restart` after each:

1. `BOX64_DYNAREC_STRONGMEM=2`, then `3`. Each step is more stable but slower.
2. `VALHEIM_BACKUPS=0`. One report links Valheim's own backups to crashes; snapshots still cover you.
3. **Not on a Pi 4?** Check that `EMULATOR_BUILD` matches your board ([table](getting-started.md#other-distributions-and-boards)), then `make build && make up`.
4. **Pin a different box64:** run `make box-versions`, set `PIN_BOX64_VERSION=<version>` in `.env`, then `make build && make up`. Known good here: `0.4.5` build `27c8275d8` (November 2026).

## Admin and console problems

| Symptom | Fix |
|---|---|
| F5 does nothing | Add `-console` to Valheim's launch options in Steam (right-click Valheim → Properties → Launch options). |
| `devcommands` says you're not an admin | Check `make admins`: is your SteamID64 there? After changing `ADMIN_IDS`, run `make restart`. Check you used the 17-digit SteamID64, not a friend code. |
| `god` (or `fly`, `ghost`, `spawn`…) "not valid in the current context" | Player cheats don't run on a dedicated server, even for admins. Use [Server devcommands](players-and-admins.md#cheats-with-server-devcommands) on your PC. |
| Commands do nothing with Server devcommands | Start Valheim **from the mod manager**, not Steam. Test with a profile that contains only that mod. |

## World settings didn't apply

- **Did it restart?** `make logs` should show `[entrypoint] World settings: …` near the start, then `Setting world modifier: …` lines once the world has loaded.
- **Removed a setting, but it's still active?** Settings are saved into the world. Set `WORLD_PRESET=normal` (or another preset) to reset everything, then `make restart`.
- **On/off settings** (`WORLD_NO_MAP` etc.) aren't logged by Valheim, so check them in game.
- See [World settings: changing an existing world](world-settings.md#changing-settings-on-an-existing-world).

## A `.env` change had no effect

- Most settings need `make restart`. Host folders, the user, CPU/memory limits and the backup schedule need `make up`. `EMULATOR_BUILD` and `PIN_BOX64_VERSION` need `make build && make up` ([details](configuration.md#how-changes-take-effect)).
- `docker compose restart` (as opposed to `make restart`) does **not** re-read `.env`. It restarts the old container with its old settings.
- Check the spelling: `make settings`. One `KEY=value` per line, no spaces around `=`.

## Memory limit ignored

Docker warns "Your kernel does not support memory limit capabilities", or `make status` shows the Pi's whole RAM as the server's limit. Raspberry Pi OS (and Ubuntu on a Pi) turn the kernel's memory controller off by default. On those:

```bash
sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak
sudo sed -i '1 s/$/ cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt   # must stay one line
sudo reboot
cat /sys/fs/cgroup/cgroup.controllers     # should include "memory"
docker compose up -d --force-recreate     # containers created before this have no limit saved
```

On other distributions, see [Other distributions and boards](getting-started.md#other-distributions-and-boards).

## Under-voltage or throttling

`throttled` in `make status` isn't `0x0`. See [Operations: power and throttling](operations.md#power-and-throttling), which explains the value, how to find when it happened, and what fixes it.

## Permission denied

In `data/` or `backups/`, or the entrypoint says `cannot write to /data`:

```bash
id -u; id -g                                      # must match PUID / PGID in .env
sudo chown -R "$(id -u):$(id -g)" /mnt/ssd/valheim # your DATA_DIR and BACKUP_DIR
```

Don't run `make` commands with `sudo`: files created as root can't be used by the server.

## Admin command errors

| Message | Meaning |
|---|---|
| `this command asks for confirmation; run it in a terminal` | Run it in an interactive shell (not through a script or pipe). |
| `run this as the user with uid 1000 (PUID in .env)` | You're another user, or using sudo. Run it as the `PUID` user. |
| `'midgard' is the active world. Switch to another first` | You can't delete the active world. Use `make world-switch NAME=<other>`. |
| `expected exactly one world folder in …` | The import file holds no world (`_main.*.fwl2`) or several. Check with `tar -tzf <file> \| head`. |
| `world names here may only use letters, digits, _ and -` | Rename the world folder (on the PC, rename it in Valheim's world menu). |
| `make players` count looks wrong | It counts joins and leaves since the last server start. If the log no longer reaches back that far, it says so and shows Valheim's own count instead. |

## Harmless messages in the log

Under emulation and without graphics, these are expected and can be ignored. `make errors` hides them.

| Message | Why |
|---|---|
| `Error initializing native libpulse.so…` (and `libpulse-simple`, `libpulse-mainloop-glib`) | No sound system in the container; the server doesn't need one. |
| `DllNotFoundException: libParty.so` | Crossplay library, intentionally missing. |
| `Error initializing native libSDL3.so.0` | The same: crossplay. |
| `AsyncResourceUpload failed`, `The referenced script on this Behaviour … is missing!` | Graphics-related; there's no GPU in a server. |
| `GPU Device: 0000:0000 (Unknown)` | The same. |
| `Failed to place all <thing>` | World generation couldn't fit every instance of a location. Normal in vanilla too. Bosses and the trader are placed first. |
| `Loading: Done, Total time: -43.3` | The negative time is a Unity timer quirk. |
| `Signal 24` / `Signal 30` | Mono's garbage collector. Only shown with `BOX64_SHOWSEGV=1`. |
| `Connections 4 sent:…` (without `ZDOS`) | An internal network statistic, not the player count. The player count line is `Connections N ZDOS:…`. |

## Digging deeper

- `make shell`: a shell inside the server container (`ls /data/server`, `ps aux`, …).
- `BOX64_LOG=1` in `.env` plus `make restart`: more box64 output. Turn it back to `0` afterwards.
- `make errors LINES=50000`: search further back in the log.
- `docker inspect valheim --format '{{.State.ExitCode}} {{.State.OOMKilled}}'`: exit code and whether memory ran out.
