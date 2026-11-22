# World settings (difficulty and world modifiers)

Valheim's **world modifiers** (the "World settings" screen when you create a world in the game) change combat difficulty, death penalty, resources, raids, portals and a few on/off rules. On a dedicated server there's no menu for them. They're launch arguments, and this project sets them from `WORLD_*` settings in `.env`.

- [Quick start](#quick-start)
- [The settings](#the-settings)
- [Changing settings on an existing world](#changing-settings-on-an-existing-world) (read this before changing a world you play on)
- [Example setups](#example-setups)
- [Checking what's active](#checking-whats-active)
- [Changing settings without a restart (admin console)](#changing-settings-without-a-restart-admin-console)
- [What these settings can't do](#what-these-settings-cant-do)
- [How it works](#how-it-works)
- [Sources and accuracy](#sources-and-accuracy)

## Quick start

On the Pi:

```bash
cd ~/valheim-server
make backup                 # world settings are saved into the world: back up first
nano .env                   # set the WORLD_* values (see below)
make restart                # applied as the server starts
make logs                   # look for "World settings: ..." near the start
```

For example, a relaxed co-op world with free-flowing portals:

```bash
WORLD_PRESET=normal
WORLD_RAIDS=less
WORLD_PORTALS=casual
```

Every value is checked when the container starts. A typo stops the server with a message naming the setting and listing the valid values, instead of being silently ignored by Valheim. Values aren't case-sensitive (`Hard` and `hard` are the same).

## The settings

Leaving a setting **empty** means "don't pass it". The world keeps whatever it already has saved (see [Changing settings on an existing world](#changing-settings-on-an-existing-world)).

| `.env` setting | Values (default in **bold**) | Server argument |
|---|---|---|
| `WORLD_PRESET` | `normal` `casual` `easy` `hard` `hardcore` `immersive` `hammer` | `-preset <value>` |
| `WORLD_COMBAT` | `veryeasy` `easy` **`normal`** `hard` `veryhard` | `-modifier combat <value>` |
| `WORLD_DEATH_PENALTY` | `casual` `veryeasy` `easy` **`normal`** `hard` `hardcore` | `-modifier deathpenalty <value>` |
| `WORLD_RESOURCES` | `muchless` `less` **`normal`** `more` `muchmore` `most` | `-modifier resources <value>` |
| `WORLD_RAIDS` | `none` `muchless` `less` **`normal`** `more` `muchmore` | `-modifier raids <value>` |
| `WORLD_PORTALS` | `casual` **`normal`** `hard` `veryhard` | `-modifier portals <value>` |
| `WORLD_NO_BUILD_COST` | `1` / **`0`** | `-setkey nobuildcost` |
| `WORLD_PLAYER_EVENTS` | `1` / **`0`** | `-setkey playerevents` |
| `WORLD_PASSIVE_MOBS` | `1` / **`0`** | `-setkey passivemobs` |
| `WORLD_NO_MAP` | `1` / **`0`** | `-setkey nomap` |

`normal` isn't a value the server accepts for a modifier: "normal" just means "no modifier". Setting a modifier to `normal` here is allowed and passes nothing. To put a modifier *back* to normal on a world that already has it changed, use `WORLD_PRESET` (see [below](#changing-settings-on-an-existing-world)).

### `WORLD_PRESET`

A bundle that sets all the modifiers at once, the same as the preset buttons in the game's World settings screen. **A preset first resets every modifier**, then sets its own. Any `WORLD_COMBAT`, `WORLD_RAIDS` and so on are applied on top of it, so you can start from a preset and adjust.

| Preset | Intent |
|---|---|
| `normal` | Standard Valheim. Also the way to **reset** a world back to default modifiers. |
| `casual` | Very forgiving: easier combat, mild death penalty, more resources, fewer raids, all items through portals. |
| `easy` | Somewhat easier than normal overall. |
| `hard` | Harder than normal overall. |
| `hardcore` | High stakes: very hard combat, harsh death penalty, restrictions such as no map. |
| `immersive` | Exploration-focused restrictions (e.g. no map, stricter portals). Includes fire spreading outside the Ashlands. |
| `hammer` | Building-focused (free building). May block some Steam achievements. |

Iron Gate doesn't publish the exact values each preset sets. To see them, create a world in the game, click a preset in World settings, and read the sliders. That's exactly what the server applies.

### `WORLD_COMBAT`

How dangerous enemies are. Harder levels make enemies bigger and faster (except in dungeons) and make starred (levelled-up) enemies more common.

| Value | Damage you deal | Damage enemies deal | Enemy speed and size | Chance of starred enemies |
|---|---|---|---|---|
| `veryeasy` | 125% | 50% | 90% | 100% |
| `easy` | 110% | 75% | 90% | 100% |
| `normal` | 100% | 100% | 100% | 100% |
| `hard` | 85% | 150% | 110% | 120% |
| `veryhard` | 70% | 200% | 120% | 140% |

### `WORLD_DEATH_PENALTY`

What happens to your items and skills when you die. Dropped items go into a tombstone where you died. Destroyed items are gone.

| Value | Items | Skill loss |
|---|---|---|
| `casual` | Keep equipped items; the rest drop | 1% |
| `veryeasy` | Everything drops | 1% |
| `easy` | Everything drops | 2.5% |
| `normal` | Everything drops | 5% |
| `hard` | Equipped items drop; **everything else is destroyed** | 7.5% |
| `hardcore` | **Everything is destroyed** | **100%** (all skills reset) |

`hardcore` is unforgiving in a shared world: one death wipes that player's character progress. Make sure everyone agrees before turning it on.

### `WORLD_RESOURCES`

A multiplier on how much you get from gathering and drops. It rounds up, and doesn't apply to fish, trophies or boss drops.

| Value | Amount |
|---|---|
| `muchless` | 0.5× |
| `less` | 0.75× |
| `normal` | 1× |
| `more` | 1.5× |
| `muchmore` | 2× |
| `most` | 3× |

### `WORLD_RAIDS`

How often raids happen (e.g. "The ground is shaking", "The forest is moving"). The game checks for a raid at an interval and then rolls a chance.

| Value | Checks about every | Chance per check |
|---|---|---|
| `none` | no raids | 0% |
| `muchless` | 92 min | 10% |
| `less` | 69 min | 13% |
| `normal` | 46 min | 20% |
| `more` | 28 min | 33% |
| `muchmore` | 14 min | 67% |

`none` turns off raids. Normal enemies still spawn and attack at night.

### `WORLD_PORTALS`

Which items and situations portals allow. Descriptions are the game's own wording.

| Value | Effect |
|---|---|
| `casual` | "Allows you to bring all items with you through portals": ores, metal bars, eggs and so on can be teleported. |
| `normal` | Standard rules: ores, metals and some other items can't go through portals. |
| `hard` | "You will not be able to use portals or exit boss dungeons while a boss is active." |
| `veryhard` | "You will not be able to use portals to teleport yourself across the world" (no portal travel). |

`casual` is the most popular change for small groups: it removes the long ore-hauling trips by boat.

### On/off settings (`1` = on)

| Setting | Effect |
|---|---|
| `WORLD_NO_BUILD_COST` | Building pieces cost no materials. You still have to discover a recipe before you can build it. |
| `WORLD_PLAYER_EVENTS` | Raids follow **each player's own progress** (the bosses *they* have defeated) instead of the world's. Useful when one player is far ahead of another: a newer player won't get late-game raids at their base. |
| `WORLD_PASSIVE_MOBS` | Enemies don't attack until you attack them. |
| `WORLD_NO_MAP` | No map and no minimap. Explore by landmarks. |

## Changing settings on an existing world

**World settings are saved into the world file.** This has three consequences:

1. **Emptying a setting doesn't undo it.** If you ran with `WORLD_RAIDS=none` and then empty it, the world keeps raids off.
2. **A preset resets everything.** `WORLD_PRESET=normal` puts every modifier back to default, then applies the others you've set. Use it to undo old changes.
3. **The safest habit: always set `WORLD_PRESET`.** With a preset set, `.env` fully describes the world. A preset plus your adjustments are applied on every start, and nothing left over from earlier runs survives. Leave `WORLD_PRESET` empty only if you've never changed the world's settings, or you want it to keep what it has.

Notes:
- **Back up first** (`make backup`). If you don't like the result, restore the snapshot with `make restore FILE=...`.
- On/off settings (`WORLD_NO_MAP` and so on) are world "keys". Sources don't agree on whether a preset clears a key that was set before. If you turn one off and it stays on, see [the admin console](#changing-settings-without-a-restart-admin-console).
- Boss kills and world progress are separate from these settings. Changing modifiers or presets doesn't reset them.
- These settings live on the server. Players don't change anything on their side.

## Example setups

Relaxed co-op (the most common small-group setup):
```bash
WORLD_PRESET=normal
WORLD_PORTALS=casual
WORLD_RAIDS=less
```

One player far ahead of the other:
```bash
WORLD_PRESET=normal
WORLD_PLAYER_EVENTS=1
```

Building weekend (then switch back to `normal` with no other settings):
```bash
WORLD_PRESET=normal
WORLD_NO_BUILD_COST=1
WORLD_PASSIVE_MOBS=1
WORLD_RAIDS=none
```

A challenge:
```bash
WORLD_PRESET=hard
WORLD_NO_MAP=1
WORLD_PORTALS=hard
```

## Checking what's active

- **The container log** lists the arguments it passed: `make logs` and look for `[entrypoint] World settings: -preset normal -modifier portals casual ...`. If it says `none set in .env`, nothing was passed and the world uses whatever it has saved.
- **Valheim's own log** confirms the preset and each modifier once the world has loaded, e.g. `Setting world modifier preset: normal` and `Setting world modifier: portals->casual`. Search with `make logs | grep -i "world modifier"`. On/off settings (`-setkey`) are **not** logged, so check those in game.
- **In the game:** test the rules (e.g. take ore through a portal, or check whether the map opens).

## Changing settings without a restart (admin console)

Admins (your SteamID64 in `ADMIN_IDS`) can change world settings live from the **F5** console after typing `devcommands`. These commands come from community sources and aren't in Iron Gate's server guide, so treat them as "try it":

| Command | Effect |
|---|---|
| `setworldpreset <preset>` | Apply a preset (`setworldpreset default` or `normal` resets all modifiers) |
| `setworldmodifier <key> <value>` | e.g. `setworldmodifier raids less` |
| `resetworldkeys` | Clear world keys **without** losing boss progress |
| `listkeys` | Show the world's current keys |
| `setkey <key>` / `removekey <key>` | Turn a key on or off (may need [Server devcommands](players-and-admins.md#cheats-with-server-devcommands)) |

**Avoid `resetkeys`.** It also clears boss kills, which resets world progress such as raids and which enemies spawn.

On the next restart, the `WORLD_*` settings in `.env` are applied again. A live change sticks only if `.env` agrees with it, or the setting is empty and no preset is set.

## What these settings can't do

- **Seed:** a dedicated server can't take a seed. To use one:
  1. Create the world in the game on your PC with that seed (single player) and load it once. Give it a name with only letters, digits, `_` and `-`.
  2. Copy its folder, `worlds_local\<name>`, from your PC to the Pi (on Windows: `%USERPROFILE%\AppData\LocalLow\IronGate\Valheim\worlds_local\<name>`).
  3. On the Pi: `make world-import FILE=<that folder>`, then `make world-switch NAME=<name>`.

  The world's settings come from the `WORLD_*` values in `.env` (if a preset is set), not from what you picked on the PC.
- **Separate settings for some newer rules,** such as fire spreading outside the Ashlands (part of the `immersive` preset) or a separate "no craft cost": Iron Gate documents no server argument for these. Use the preset that includes them, or `EXTRA_SERVER_ARGS` if a future update adds one.
- **Anything per player:** these are world-wide settings for everyone.

## How it works

`docker/entrypoint.sh` turns the settings into arguments in this order:

```
valheim_server ... -preset <p> -modifier <key> <value> ... -setkey <key> ... <EXTRA_SERVER_ARGS>
```

The preset comes first because it overwrites any modifier set before it. `EXTRA_SERVER_ARGS` comes last, so anything you put there is applied after the `WORLD_*` settings.

## Sources and accuracy

The setting names and values match across every source and the game's own World settings screen. The numbers in the effect tables (combat, death penalty, resources, raids) were measured by the community (the Valheim wiki, as quoted by the sources below), not published by Iron Gate. Where sources disagree, this guide says so: on whether a preset clears on/off keys, and on which admin commands work on a dedicated server. If something behaves differently in your game, trust the game.

- Iron Gate: dedicated server guide (in the server download as `Valheim Dedicated Server Manual.pdf`; it lists `-preset`, `-modifier` and `-setkey`)
- [Connect Hosting: Valheim world modifiers, every value, preset and command](https://connecthosting.net/blog/valheim-world-modifiers-dedicated-server)
- [GameServerKings: Valheim world modifiers on a dedicated server](https://www.gameserverkings.com/knowledge-base/valheim/valheim-world-modifiers/)
- [Valheim Companion: world modifiers](https://www.valheimcompanion.com/world/world-modifiers)
