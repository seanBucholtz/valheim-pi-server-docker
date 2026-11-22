# Players and admins

- [Joining](#joining)
- [Who's playing: player history](#whos-playing-player-history)
- [Steam profiles](#steam-profiles)
- [Admins and the console](#admins-and-the-console)
- [Cheats with Server devcommands](#cheats-with-server-devcommands)
- [Kicking, banning and allow-listing](#kicking-banning-and-allow-listing)
- [Finding a SteamID64](#finding-a-steamid64)

## Joining

In Valheim: **Join Game → Join IP** → `192.168.1.50:2456` → the password (`SERVER_PASSWORD`).

- Wait for `make status` to show `healthy`, or use `make wait`. Before that, joining fails with "failed to connect".
- The client and server must run **the same Valheim version**. After a game update, `make restart` updates the server.
- From outside your home network: set `SERVER_PUBLIC=1`, and forward UDP 2456-2457 on your router to the Pi. Crossplay (Xbox / Game Pass) isn't available ([why](architecture.md#design-decisions)).
- Each player's character (skills, inventory) is stored **on their own PC**, so they bring it to any world.

## Who's playing: player history

The server records joins, leaves, characters and deaths in `DATA_DIR/players.log` **as they happen**. It survives restarts, rebuilds and world switches. Example output:

```
$ make players
Connected now: 1  ->  Bjorn (76561198000000001)
  (from joins and leaves since the server started; Valheim's own count, logged
   every few minutes, says: 1)

Recent activity:
  19:00:00  started    (server start)
  19:04:12  joined     76561198000000001
  19:04:40  spawned    Bjorn (76561198000000001)
  19:31:08  died       Bjorn
  19:31:15  respawned  Bjorn
  21:47:30  left       Astrid (76561198000000002)

Known players (since 2026-01-10); details: make player ID=<SteamID>
  STEAMID            STEAM NAME        CHARACTERS          LAST SEEN           PLAYED  DEATHS
  76561198000000001  bjorn_plays       Bjorn               online now         18h 20m       3
```

| Part | Source |
|---|---|
| **Connected now** | Joins and leaves since the last server start, from the live log. Accurate within seconds. Valheim's own count, which it writes every few minutes, is shown for comparison. |
| **Recent activity** | The live container log since the container was created. `refused` = wrong password. |
| **Known players** | `players.log`: everyone since history recording began. Steam names are looked up once and cached in `DATA_DIR/steam-names.tsv`. |

Example:

```
$ make player NAME=Bjorn                     # or: make player ID=76561198000000001
SteamID 76561198000000001
On this server (history since 2026-01-10):
  Characters:       Bjorn
  Status:           online now
  First seen:       2026-01-10 18:02:11
  Last seen:        2026-01-15 21:52:03
  Sessions:         6
  Play time:        18h 20m
  Deaths:           3
  Worlds:           midgard
From Steam:
  Steam name:       bjorn_plays
  Status:           Online (Valheim)
  Profile:          public
  Member since:     January 1, 2020
  Steam profile:    https://steamcommunity.com/profiles/76561198000000001
```

Character names match case-insensitively.

**How it's worked out:**
- Valheim logs `Got handshake from client <SteamID>` (joined), then `Got character ZDOID from <name> : <id>` (spawned). A name is linked to the most recent join that has no name yet.
- An ID of `0:0` means the character died. A new ID after that is a respawn.
- `Closing socket <SteamID>` means the player left.

**Limits:**
- Two players joining within the same few seconds could get their names swapped.
- Play time is counted from join to leave. If the server crashes instead of stopping cleanly, a session ends at the last recorded event.
- History starts when recording was installed; earlier sessions aren't included.
- Levels, skills and inventory can't be shown, because they're on each player's PC.

## Steam profiles

`make player`, and the Steam name column in `make players`, ask Steam about a SteamID. **Only the SteamID is sent, and only to Steam.**

| | Without a key | With `STEAM_API_KEY` |
|---|---|---|
| Source | Public profile page (`steamcommunity.com/profiles/<id>?xml=1`) | Steam Web API |
| Always | Steam name, online status, profile privacy, avatar, VAC-ban flag, profile link | Steam name, status, current game, profile privacy, last logoff, profile link |
| If the profile is public | Real name, member since, location, hours in the last 2 weeks, current game | Real name, account created, country, **total Valheim hours** |

To get a key: sign in at [steamcommunity.com/dev/apikey](https://steamcommunity.com/dev/apikey), enter any domain name (e.g. `localhost`), and put the key in `.env` as `STEAM_API_KEY=…`. It's used straight away, with no restart. `make settings` hides it.

A player's **login name** is never visible; Steam doesn't publish it. Names that couldn't be looked up show as `?` and are retried after a day. Running `make player` for someone refreshes their cached name.

## Admins and the console

1. **Find your SteamID64** ([how](#finding-a-steamid64)).
2. **Add it to `.env`:** `ADMIN_IDS=76561198000000000`. For several people, separate the IDs with spaces or commas.
3. **Apply:** `make restart`. At every start the container rewrites `worlds/adminlist.txt` from `ADMIN_IDS` (as `Steam_<id>` and the bare ID). If `ADMIN_IDS` is empty, the file is left alone, so you can manage it by hand instead. `make admins` shows the result.
4. **In game:** press **F5** for the console and type `devcommands`. The server log confirms you with `Remote admin '<id>' executed command 'devcommands' remotely.`
   - If F5 does nothing, add `-console` to Valheim's launch options in Steam (right-click Valheim → Properties → Launch options).

**On this vanilla dedicated server, admins can use:**
- server commands: `kick`, `ban`, `unban`, `banned`;
- world commands: `sleep`, `skiptime`;
- live world settings: `setworldmodifier`, `setworldpreset` ([World settings](world-settings.md#changing-settings-without-a-restart-admin-console)).

**Player cheats** (`god`, `ghost`, `fly`, `debugmode`, `spawn`, …) only run on the machine hosting the world. Here they fail with "not valid in the current context", even for admins. Use [Server devcommands](#cheats-with-server-devcommands) for those.

Anything spawned or built with cheats stays in the shared world, so back up first: `make backup`.

## Cheats with Server devcommands

[Server devcommands](https://thunderstore.io/c/valheim/p/JereKuusela/Server_devcommands/) by JereKuusela lets admins use the normal cheat commands on a dedicated server. It's installed **only on the gaming PC of each admin who wants cheats**. The Pi stays vanilla, and players without the mod join as normal.

1. **Be an admin on the server** (above). The mod checks this.
2. **Install a mod manager** on your PC, e.g. [r2modman](https://thunderstore.io/c/valheim/p/ebkr/r2modman/). Choose **Valheim** and create a profile, e.g. `admin`. Profiles keep mods separate from your normal install.
3. **Install the mod:** search the online mods for **Server devcommands** by JereKuusela, install it, and accept its dependency, **BepInExPack Valheim**. Don't use the older, deprecated **Dedicated server devcommands**.
4. **Start Valheim from the mod manager** ("Start modded"). Starting from Steam runs vanilla Valheim.
5. **Join**, press **F5**, enter `devcommands`, then e.g. `god`, `ghost`, `fly`, `debugmode` (**Z** to fly, **B** to build for free), `spawn Wood 50` or `pos`.

Notes:
- A few commands need the mod on the server too (e.g. `event`, `randomevent`, `stopevent`, `find`). This server runs no mods, so those won't work.
- After a Valheim update the mod can break until its author catches up. Update it in the mod manager, or play vanilla from Steam meanwhile.
- If nothing works with the mod loaded, test with a profile that holds only Server devcommands. Another mod may be patching the console.

## Kicking, banning and allow-listing

| To… | Do |
|---|---|
| Kick someone now | Console: `kick <name or SteamID>` |
| Ban | Console: `ban <name or SteamID>`. This adds them to `worlds/bannedlist.txt`. |
| Unban | Console: `unban <SteamID>`, or remove the line from `bannedlist.txt` |
| See bans | Console: `banned`, or `make admins` |
| **Only** let certain people in | Put their SteamID64s, one per line, in `DATA_DIR/worlds/permittedlist.txt`. While the file is empty, anyone with the password can join. |

`make admins` shows all three lists. After hand-editing a list, run `make restart` to make sure the server has re-read it.

## Finding a SteamID64

A SteamID64 is a 17-digit number starting with `7656119`.

- **In Valheim:** press **F2** while connected. Players are listed as `Steam_7656…`.
- **In Steam:** click your account name (top right) → **Account details**. It's shown as "Steam ID".
- **From a profile URL** like `steamcommunity.com/profiles/7656…`.

Neither a custom `/id/<name>` URL nor a friend code contains it. For other players, `make players` shows the SteamIDs of everyone who has joined.
