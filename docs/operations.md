# Operations

Running the server day to day: checking on it, updating it, and keeping the Pi happy.

- [Everyday routine](#everyday-routine)
- [Checking on the server](#checking-on-the-server)
- [Updates](#updates)
- [Restarts, reboots and power cuts](#restarts-reboots-and-power-cuts)
- [Power and throttling](#power-and-throttling)
- [Performance](#performance)
- [Disk space and SD-card wear](#disk-space-and-sd-card-wear)

## Everyday routine

There isn't much to do: the server starts with the Pi, saves on its own, and takes snapshots on its own.

| When | Do |
|---|---|
| Before playing | `make status`: is it `healthy`? |
| After a Valheim update (you get "version mismatch") | `make restart && make wait` |
| Before anything risky (cheats, new world settings, imports) | `make backup` |
| Now and then | `make errors`, `make backups` (space), and copy backups off the Pi |

## Checking on the server

```
$ make status
NAME             ...   STATUS
valheim          ...   Up 3 hours (healthy)
valheim-backup   ...   Up 3 hours
NAME             CPU %     MEM USAGE / LIMIT
valheim          85.0%     2.0GiB / 5GiB
valheim-backup   0.00%     2.0MiB / 7.6GiB
temp=52.0'C
throttled=0x0
```

| Look at | Good | Worry when |
|---|---|---|
| Health | `healthy` = joinable | `starting` for more than ~5 min (existing world) or ~25 min (new world); `unhealthy` |
| CPU % | Up to ~100-150 % with two players (one or more cores) | Steadily near 300 %: the server is maxing out its 3 cores |
| Memory | 1.5-2.5 GiB of 5 GiB | Getting close to the limit (the server would be restarted) |
| Temperature | Below ~70 °C | Above 80 °C: the Pi slows itself down. Add a heatsink and fan, or a better case. |
| `throttled` | `0x0` | Anything else, see [Power and throttling](#power-and-throttling) |

**Logs:** `make logs` follows the live log, and `make errors` shows only real errors. Many alarming-looking lines are normal under emulation: see [harmless messages](troubleshooting.md#harmless-messages-in-the-log).

**Players:** `make players` shows who's on, live. Check it before any restart.

## Updates

| What | How | Notes |
|---|---|---|
| **Valheim server** | `make restart` | With `UPDATE_ON_START=1`, every start checks Steam and downloads updates (`-validate` also repairs damaged files). Update when the game client updates, or you'll get a version mismatch. |
| **box64** | `make update` | Rebuilds the image with the newest box64 build. New builds sometimes break Valheim; if so, pin a known-good one ([Troubleshooting](troubleshooting.md#the-server-crashes-after-someone-joins-or-after-a-few-hours)). The Pi-Apps-Coders repository only keeps the last few builds, so note the version that works (`make logs` shows it at start). |
| **DepotDownloader** | Edit `DEPOTDOWNLOADER_VERSION` and `DEPOTDOWNLOADER_SHA256` in `Dockerfile`, then `make build && make up` | Only needed if Steam changes something and downloads start failing. |
| **Debian base image** | `make build && make up` | `make build` pulls the latest `bookworm-slim`. |
| **Host OS** | `sudo apt update && sudo apt full-upgrade` (Raspberry Pi OS, Debian, Ubuntu), then reboot | The containers come back by themselves. Check `make status` afterwards. |
| **This project** | See [Getting started](getting-started.md#updating-the-project-later) | Keep `.env`, `data/` and `backups/`. |

Before `make update` or `make build`: `make players`, then `make backup`.

## Restarts, reboots and power cuts

| Event | What happens |
|---|---|
| `make restart` | Clean stop (world saved), then a fresh container with the current `.env`. The server updates, then loads. |
| `make down` / `make up` | Clean stop, containers removed / created again. **After `make down` the server stays off**, even across reboots, until `make up`. |
| Pi reboot (`sudo reboot`) | Docker stops the containers cleanly (world saved), and they start again after boot (`restart: unless-stopped`). |
| Server crash | Docker restarts it. Progress since the last save (up to `SAVE_INTERVAL`) is lost. |
| **Power cut** | No clean stop: progress since the last save is lost. A cut mid-save can damage the newest save generation, which is what [Valheim's backups and snapshots](backups.md) are for. |

A clean stop can take up to 120 seconds while the world saves; Docker waits that long before killing the server. Don't unplug the Pi to turn it off: run `sudo shutdown -h now` and wait for the green light to stop flashing.

## Power and throttling

On a Raspberry Pi, `vcgencmd get_throttled` (shown in `make status`) reports power and temperature problems:

| Bit | Value | Meaning |
|---|---|---|
| 0 | `0x1` | Under-voltage **now** |
| 1 | `0x2` | ARM frequency capped **now** |
| 2 | `0x4` | Throttled **now** |
| 3 | `0x8` | Soft temperature limit **now** |
| 16 | `0x10000` | Under-voltage has happened since boot |
| 17 | `0x20000` | Frequency capping has happened |
| 18 | `0x40000` | Throttling has happened |
| 19 | `0x80000` | Soft temperature limit has happened |

For example, `0x50000` = under-voltage and throttling **have happened** since boot, but neither is happening now.

**Under-voltage** is the common one on a Pi 4 with a USB SSD. The SSD draws its power through the Pi, and the dips land exactly when the server is busy and saving. To find when it happened:

```bash
sudo journalctl -k -b | grep -iE 'voltage|throttl'
```

| Fix | |
|---|---|
| Use a **5.1 V / 3 A** supply: the official Raspberry Pi one, or one made for the Pi 4 (e.g. CanaKit 3.5 A) | The extra 0.1 V covers cable losses. Phone and laptop chargers deliver 5.0 V to a Pi 4. |
| Short, thick cable; no USB-C hubs in between | |
| If dips continue: power the SSD separately (a powered USB 3 hub, or a case with its own power input) | |

To check whether the SSD has ever dropped out during a dip:

```bash
sudo journalctl -k -b | grep -iE 'usb .*(reset|disconnect)|I/O error'
```

No output is good.

## Performance

**Tested with two players** on a Pi 4. More may work: Valheim allows up to 10, but under emulation the CPU is the limit, and every player exploring a different area adds world generation and simulation work. Watch CPU in `make status` as more people join. Even with two, expect occasional lag during big fights, heavy building, or sailing into newly generated areas, because new terrain is generated on the server.

The server and backups run on cores **1-3** (`SERVER_CPUS`). Core 0 is left free, so the Pi stays responsive (SSH, a desktop, anything else it runs) even when the server is busy. If nothing else runs on the Pi, `SERVER_CPUS=0-3` (then `make up`) gives the server the whole CPU.

| Symptom | Try |
|---|---|
| Lag spikes | Check `throttled` and the temperature first. Then fewer things at once: big bases with many lights and fires are expensive. |
| Lag after exploring a lot | Normal: the world grows (`make worlds`). Saves take longer as it grows. |
| Crashes when someone joins | box64 tuning, see [Troubleshooting](troubleshooting.md#the-server-crashes-after-someone-joins-or-after-a-few-hours). |
| Stutter every 30 minutes | That's the save (`SAVE_INTERVAL`). A longer interval means fewer stutters but more to lose in a crash. |

## Disk space and SD-card wear

| What | Size | Where |
|---|---|---|
| Server files | ~1 GB | `DATA_DIR/server` |
| A world | 5-100 MB, growing with exploration | `DATA_DIR/worlds/worlds_local` |
| Snapshots | All worlds × `BACKUP_KEEP` | `BACKUP_DIR` |
| Docker images | ~1 GB, more after rebuilds | SD card (`/var/lib/docker`). Clean up with `make clean-images`. |
| Container logs | Up to 3 × 10 MB per container | SD card |

With `DATA_DIR` and `BACKUP_DIR` on the SSD, the SD card only holds the OS, Docker's images and the logs, so frequent saves don't wear it out. Check space with `df -h / /mnt/ssd` or `make backups`.
