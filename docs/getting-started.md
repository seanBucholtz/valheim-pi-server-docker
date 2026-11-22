# Getting started

From a fresh Raspberry Pi to a joinable server. Every command runs **on the Pi**, from the project folder (`~/valheim-server` in the examples), unless it says otherwise.

- [What you need](#what-you-need)
- [1. Prepare the Pi](#1-prepare-the-pi)
- [2. Put the data on the USB SSD](#2-put-the-data-on-the-usb-ssd) (recommended)
- [3. Get the project onto the Pi](#3-get-the-project-onto-the-pi)
- [4. Configure](#4-configure)
- [5. Turn on the memory limit](#5-turn-on-the-memory-limit)
- [6. Build and start](#6-build-and-start)
- [7. Connect](#7-connect)
- [What to do next](#what-to-do-next)
- [Other distributions and boards](#other-distributions-and-boards)
- [Updating the project later](#updating-the-project-later)

## What you need

| | Requirement | Notes |
|---|---|---|
| **Pi** | Raspberry Pi 4, 8 GB (4 GB is tight) | Tested with two players; more may work ([Performance](operations.md#performance)). Other boards: see [below](#other-distributions-and-boards). |
| **OS** | Raspberry Pi OS **64-bit** (Bookworm) is tested | `uname -m` must say `aarch64`. Other 64-bit distributions should work, with a few differences ([below](#other-distributions-and-boards)). |
| **Power** | A **5.1 V / 3 A** USB-C supply: the official Raspberry Pi supply, or one built for the Pi 4 (e.g. CanaKit 3.5 A) | Phone and laptop chargers usually give 5.0 V, which dips under load, especially with a USB SSD attached. See [Operations: power](operations.md#power-and-throttling). |
| **Storage** | A USB 3 SSD for the data (recommended) | The SD card works, but it's slower and wears out under constant saves. About 10 GB is plenty: the server is ~1 GB, and worlds and backups add more over time. |
| **Network** | Ethernet, and a fixed address (DHCP reservation) | The examples use `192.168.1.50`. |
| **Software** | Docker Engine with the compose plugin | `make setup` checks this. |

## 1. Prepare the Pi

```bash
# Docker (official convenience script), then let your user run it
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER          # log out and back in afterwards
docker compose version                 # should print a version
```

On your router, give the Pi a **DHCP reservation** so its address never changes.

## 2. Put the data on the USB SSD

Skip this step to keep everything on the SD card. You can move later (see [Moving to the SSD later](#moving-to-the-ssd-later)).

1. **Partition and format** an ext4 partition on the SSD, for example with GParted on a desktop or `sudo mkfs.ext4 -L valheim /dev/sdX1` on the Pi. **This erases the partition.** Check the device name with `lsblk` first.
   - The SSD can hold other partitions too, for example an exFAT one for moving files to and from a PC. The server only needs one ext4 partition.
   - Use **ext4**, not exFAT or NTFS: the server needs Linux file permissions.
2. **Mount it permanently:**
   ```bash
   sudo mkdir -p /mnt/ssd
   lsblk -f                                               # note the ext4 partition's UUID or LABEL
   echo 'LABEL=valheim /mnt/ssd ext4 defaults,noatime,nofail 0 2' | sudo tee -a /etc/fstab
   sudo mount -a && sudo chown "$USER": /mnt/ssd
   mkdir -p /mnt/ssd/valheim/data /mnt/ssd/valheim/backups
   ```
   `nofail` lets the Pi still boot if the SSD is unplugged. Reboot once and check that `/mnt/ssd` is mounted (`findmnt /mnt/ssd`).

## 3. Get the project onto the Pi

Clone it on the Pi (any folder works; the docs use `~/valheim-server`):

```bash
sudo apt install -y git make
git clone https://github.com/seanBucholtz/valheim-pi-server-docker.git ~/valheim-server
cd ~/valheim-server
```

Or copy a folder from your PC, for example with `rsync`:

```bash
# on your PC, from the project folder
rsync -a --exclude=.env --exclude=data --exclude=backups --exclude=.git ./ <user>@192.168.1.50:valheim-server/
```

When updating an existing install, **never overwrite the Pi's `.env`, `data/` or `backups/`**. `git pull` never touches them, because they aren't part of the repository, and the excludes above take care of the copy.

## 4. Configure

```bash
cd ~/valheim-server
make setup        # first run: creates .env (from .env.example) and stops
nano .env         # edit, see below
make setup        # second run: checks Docker, PUID/PGID, folders, swap
```

In `.env`, set at least:

```bash
SERVER_NAME=Our Valheim          # shown in game
WORLD_NAME=Midgard               # letters, digits, _ and - (no dots); created if it doesn't exist
SERVER_PASSWORD=...              # at least 5 characters, not part of SERVER_NAME
DATA_DIR=/mnt/ssd/valheim/data          # if you did step 2
BACKUP_DIR=/mnt/ssd/valheim/backups
ADMIN_IDS=7656119...             # optional: your SteamID64, for the admin console
```

Also look at the [world settings](world-settings.md) (difficulty, portals, raids…) **before the first start**, because a new world is created with them. Every setting is explained in [Configuration](configuration.md).

`make setup` offers to raise swap to 2 GB. Accept: Raspberry Pi OS ships with 512 MB. On other distributions it only warns, and you add swap yourself ([below](#other-distributions-and-boards)). It also checks that `EMULATOR_BUILD` suits your board.

## 5. Turn on the memory limit

Docker can only enforce the server's `MEMORY_LIMIT` if the kernel's memory controller is on. Check first:

```bash
cat /sys/fs/cgroup/cgroup.controllers     # includes "memory"? then skip to step 6
```

Raspberry Pi OS (and Ubuntu on a Pi) ships with it off, so Docker ignores the limit (you'd see a "memory limit capabilities" warning). Turn it on once:

```bash
sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.bak
sudo sed -i '1 s/$/ cgroup_enable=memory cgroup_memory=1/' /boot/firmware/cmdline.txt
cat /boot/firmware/cmdline.txt            # must still be ONE line, ending in those two words
sudo reboot
cat /sys/fs/cgroup/cgroup.controllers     # after the reboot: should include "memory"
```

Doing this before the first `make up` means you don't have to recreate the containers afterwards.

## 6. Build and start

```bash
make build        # builds the arm64 image (~5-10 minutes)
make up           # starts the server and the backup sidecar
make wait         # returns when the server is joinable
```

The first start takes the longest: the server (~1 GB) downloads, then the world is generated (10-20 minutes on a Pi 4). `make logs` shows progress. The world-generation messages `Failed to place all ...` are normal. Further starts take 2-3 minutes.

## 7. Connect

In Valheim: **Join Game → Join IP** → `192.168.1.50:2456`, then the password. On the same home network you don't need port forwarding.

If it says "failed to connect", check `make status`. Until it says `healthy`, the server isn't ready yet.

## What to do next

- [Make yourself an admin](players-and-admins.md#admins-and-the-console) and learn the console.
- Read [Operations](operations.md): updates, monitoring, power, performance.
- Look at [Backups](backups.md), and plan to copy them off the Pi eventually.
- Keep `make help` handy, or the [Commands](commands.md) reference.

## Moving to the SSD later

```bash
make down
# mount the SSD as in step 2, then:
rsync -a data/ /mnt/ssd/valheim/data/
rsync -a backups/ /mnt/ssd/valheim/backups/
nano .env      # DATA_DIR=/mnt/ssd/valheim/data   BACKUP_DIR=/mnt/ssd/valheim/backups
make up && make wait
```

Keep the old `data/` until you've played on the SSD copy, then delete it.

## Other distributions and boards

Only Raspberry Pi OS 64-bit (Bookworm) on a Pi 4 is tested. The container runs Debian whatever the host runs, though, so the host only has to provide:

- a **64-bit ARM** kernel: `uname -m` says `aarch64`;
- **4 KB memory pages**: `getconf PAGESIZE` says `4096`. A Pi 5's default kernel uses 16 KB pages: add `kernel=kernel8.img` to `/boot/firmware/config.txt` and reboot;
- **Docker** with the compose plugin, plus `git` and `make`;
- **enough memory**: the server uses 1.5-2.5 GB, so 4 GB of RAM is the practical minimum.

What's different from the steps above:

| | On Raspberry Pi OS | Elsewhere |
|---|---|---|
| **box64 build** | `EMULATOR_BUILD=rpi4` (the default) | Set `EMULATOR_BUILD` in `.env` before `make build` (table below). |
| **Memory limit** ([step 5](#5-turn-on-the-memory-limit)) | Off by default: edit `cmdline.txt` | Often already on, so check first. If not, add `cgroup_enable=memory cgroup_memory=1` to the kernel command line the way your distribution does it (for GRUB: `GRUB_CMDLINE_LINUX` in `/etc/default/grub`, then `sudo update-grub`). |
| **Swap** | `make setup` raises it to 2 GB | Check with `swapon --show` (some distributions use zram). For a 2 GB swap file, see below. |
| **Temperature, throttling** | Shown by `make status` | Not shown: `vcgencmd` only exists on a Raspberry Pi. |
| **Power** | 5.1 V / 3 A supply ([why](operations.md#power-and-throttling)) | Use the supply your board's maker recommends. |

**`EMULATOR_BUILD`** picks the box64 build, each tuned for a CPU. Apply a change with `make build && make up`:

| Value | For |
|---|---|
| `rpi4` | Raspberry Pi 4, Pi 400, Compute Module 4 (default) |
| `rpi3` | Raspberry Pi 3. Its 1 GB of RAM is too little for Valheim. |
| `rk3399` | RK3399 boards (Rock Pi 4, NanoPC-T4, Pinebook Pro, …) |
| `tegrax1` | NVIDIA Jetson Nano |
| `generic` | Any other 64-bit ARM: Raspberry Pi 5, RK3588 boards (Orange Pi 5, Rock 5), ARM cloud servers, … |

**A 2 GB swap file** (where `make setup` can't add one):

```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

**`SERVER_CPUS`** defaults to `1-3`, which suits a 4-core board. On a board with more cores, give the server more of them, for example `1-7` on an 8-core RK3588.

## Updating the project later

1. Get the new version: `git pull` in the project folder, or copy the files over as in [step 3](#3-get-the-project-onto-the-pi), keeping `.env`, `data/` and `backups/`.
2. Compare `.env.example` with your `.env`, and add any new settings you want (missing ones use their defaults).
3. Apply the changes:
   - If `Dockerfile` or `docker/entrypoint.sh` changed: `make backup && make build && make up`.
   - If only `Makefile`, `scripts/` or docs changed: nothing to restart.
