# Playtest Checkpoints

Each checkpoint is a "stop, test this, confirm it works before we go further"
gate in the four-god-squad build. Instructions are self-contained; you
shouldn't need anything else to run them.

---

## Checkpoint 1 — ZetaBot alive in UZDoom

**Goal:** Confirm ZetaBot loads without compile errors and can spawn one
bot that follows you. This validates the core bot framework before we
layer personas, PB3 weapon handling, or squad logic on top.

### Isolated sanity test (run this first)

Launch with vanilla Doom 2 only — no PB3, no Maps of Chaos, no hearth-logger.
This isolates whether ZetaBot itself loads cleanly in UZDoom 4.14.3.

```cmd
uzdoom.exe ^
  -iwad doom2.wad ^
  -file D:\Users\Dan\dev\doom-copilot\zetabot-fork ^
  +map MAP01 ^
  -skill 2
```

Once in the level, drop the console (`` ` ``) and run:

```
summonfriend zetabot 0
```

**Pass criteria:**
- Game loads with no red ZScript compile errors at startup
- A bot spawns near you when you run the command
- The bot follows you as you move (may be clumsy — that's fine)
- You can kill the bot with `kill ZetaBotPawn` from the console

**If it fails:**
- **Compile error at startup** → ZetaBot's `version "2.5"` is too old for UZDoom 4.14.3. Fix: bump version in `zetabot-fork/ZScript.zs` line 1 to `"4.0"` or `"4.14.2"`.
- **`summonfriend` not a command** → check you're typing into the drop-down console, not the chat
- **Bot spawns but stands still** → there are no path nodes on MAP01. Press Numpad 7 (`zt_showpaths`) to confirm. Fix by dropping nodes with Numpad 2 (or enabling `zb_autonodes 1`).
- **Something else** → report the error, we diagnose.

### Integration test (only if isolated passes)

Once the isolated test passes, try the full load chain including PB3 + hearth-logger + silencer:

```cmd
uzdoom.exe ^
  -iwad doom2.wad ^
  -file D:\Users\Dan\games\DOOM\Project_Brutality-master ^
         D:\Users\Dan\dev\doom-copilot\zetabot-fork ^
         D:\Users\Dan\dev\doom-copilot\logger\hearth-logger ^
         D:\Users\Dan\dev\doom-copilot\hearth-silencer ^
  +map MAP01 ^
  -skill 2
```

Then `summonfriend zetabot 0` again.

**Pass criteria (integration):**
- No compile errors from the combined ZScript
- HUD is silent (no pickup spam, no PBMonsterArmor messages) — confirms hearth-silencer works
- Bot still spawns and follows
- Bot picks up PB3 weapons (will be confused by class names — this is expected, fixed in Item 7)

**If the silencer breaks HUD rendering entirely (no health bar visible):** the `StatusBarClass` swap went wrong. Remove `hearth-silencer` from the load chain and re-test; we'll debug separately.

---

## Checkpoint 2 — Squad Deploy preset spawns 3 bots

**Goal:** Verify the launcher preset composes the right mod stack, the
auto-spawner deploys the squad on map load, and the four personas are
visibly distinct in their early behavior.

### Launch

Double-click **[launch/squad_deploy.bat](../launch/squad_deploy.bat)**,
or from a terminal:

```
cd D:\Users\Dan\dev\doom-launcher
py -3 doom_launcher.py --profile squad_deploy
```

Loads Doom 2 + PB3 + brightmaps + Maps of Chaos + hearth-logger +
zetabot-fork + hearth-silencer + copilot-mod. Drops you into MAP01
of Maps of Chaos on skill 5 (Nightmare).

### Pass criteria

Within 1 second of the map loading:
- Console prints `Doom Copilot: auto-deploying squad at Pilot position`
- Three `Doom Copilot: deployed <Persona>` lines follow
- Three bots visible around you (Sharpshooter, Tank, Brawler flavors)
- HUD is silent of PB3 message spam (hearth-silencer working)
- hearth-logger running (no pickup spam, logging to data/session_*.log)

### Behavioral checks — are personas visibly distinct?

- **Sharpshooter** hangs back further than the others (follow dist 400/250)
- **Tank** sticks tight to you (follow dist 180/120)
- **Brawler** rushes forward, aggressive on engagements (flee at only 15% HP)
- **Death-Wish** — NOT in auto-deploy squad; test with **F9** keybind.
  Should ignore you entirely and charge whatever's nearest.

### Key bindings

- **F5** — deploy Sharpshooter+Tank+Brawler squad (same as auto-spawn)
- **F6** — summon Sharpshooter
- **F7** — summon Brawler
- **F8** — summon Tank
- **F9** — summon Death-Wish (chaos bot)
- **F12** — kill all bots (dc_disband)
- **o** — order nearby bots to follow you (ZetaBot default)
- **u** — disband follow order
- **p** — order attack on what you're aiming at

### If it fails

- **Bots don't auto-spawn** → check `dc_autospawn_squad` in console: `get dc_autospawn_squad`. Should be 1.
- **Only 1 or 2 bots spawn** → spacing issue at spawn; the bots may overlap. Move and try F5.
- **Bots stand still** → check `get zb_autonodes` (should be 1). Press Numpad 7 to see nodes.
- **Bots don't attack anything** → this is Item 7 territory (PB3 weapon module). They recognize vanilla weapons only right now, so combat will feel broken until Item 7 ships.
- **Any VM abort** → copy the error, we diagnose.

---

## Checkpoint 3 — Bots use PB3 weapons intelligently

*(Unlocks after Checkpoint 2 passes. Filled in when Items 7+8 land.)*

---

## Checkpoint 3 — Bots use PB3 weapons intelligently

*(Unlocks after Checkpoint 2 passes. Filled in when Items 7+8 land.)*

---

## Checkpoint 4 — Full system playtest

*(Unlocks after Checkpoint 3 passes. Filled in when Item 10 lands.)*
