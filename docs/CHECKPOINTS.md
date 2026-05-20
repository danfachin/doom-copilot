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

The squad is now an overlay toggle in the doom-launcher GUI
(`C:\Games\DOOM\launcher\doom_launcher.py`). To deploy:

1. Open the launcher (any shortcut, or `py -3 doom_launcher.py` from the
   launcher dir).
2. In the **Library** tab toolbar, flip the **Four-God Squad** switch ON.
   The status bar at the bottom confirms `★ Four-God Squad ON`.
3. Pick any Library card (Maps of Chaos for the original target, or
   anything else — squad rides every launch while the toggle is on)
   and hit **PLAY**.

Squad ON appends `hearth-logger + zetabot-fork` after the regular pre-stack
and `copilot-mod` after the silencer, plus the `+dc_autospawn_squad 1`,
`+dc_debug 0`, `+zb_autonodes 1`, `+zb_autonodenormal 0` CVars — same load
order as the legacy squad_deploy.bat (now deleted). When OFF, none of those
bits ride along.

`dc_debug` shipped as 1 originally; flipped to 0 as the default
(2026-05-19, CHAT-CC-260519-054) since the `[DC]` event spam was a
non-trivial slice of per-tic sync-IO under combat. Re-enable on a
per-session basis via the launcher's CVar field if you want
state_change / bot_tick tracing.

The toggle persists in `always-on.json` under the `squad.enabled` key.
The switch is disabled at launcher start if any of the squad asset paths
(`logger/hearth-logger`, `zetabot-fork`, `copilot-mod`) aren't on disk.

### Pass criteria

Within 1 second of the map loading:
- Console prints `Doom Copilot: auto-deploying squad at Pilot position`
- Three `Doom Copilot: deployed <Persona>` lines follow
- Three bots visible around you (Sharpshooter, Tank, Brawler flavors)
- HUD is silent of PB3 message spam (hearth-silencer working)
- hearth-logger running (no pickup spam, logging to data/session_*.log)

### Behavioral checks — are personas visibly distinct?

- **Sharpshooter** hangs back further than the others (follow dist 400/250).
  Post-calibration (2026-05-19) plants at 300-600u from enemies (was 640-1024)
  and retreats at 64% HP (was 35%).
- **Tank** sticks tight to you (follow dist 180/120). Post-calibration retreats
  at 76% HP (was 50%), holds a Deagle sidearm (was SMG).
- **Brawler** *kites* — dashes in for ~0.8s then back out for ~0.8s on a 1.6s
  cycle, firing through both phases. Should read as constantly moving, not
  static. Retreats at 20% HP.
- **Death-Wish** — NOT in auto-deploy squad; test with **F9** keybind.
  Should ignore you entirely and charge whatever's nearest.

### Audio / console check

Squad bots run **silent** now — no BotChat voice callouts (HURT/ELIM/IDLE/
TARG/COMM etc. were overridden out 2026-05-19). The console still prints
one-shot startup messages (`Doom Copilot: auto-deploying squad...`,
`deployed <Persona>` ×3) and PB3 system messages, but combat is quiet.
If you hear ZetaBot voice barks during combat, the override isn't
binding — check that the persona class is descended from `DoomCopilotController`.

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

**Goal:** Verify the PB3 weapon module is wired up and bots are making
range-appropriate weapon choices against PB3 enemies.

### Launch

Same as Checkpoint 2: open the doom-launcher, flip **Four-God Squad** ON
in the Library toolbar, click PLAY on a Library card.

### Pass criteria

Within 30 seconds of combat starting:
- Bots pick up PB3 weapons (not stuck on pistol forever)
- At **close range** (<128u): bots pull shotguns, chainsaws, fists
- At **medium range** (256–768u): bots use DMR, Carbine, Minigun, SSG
- At **long range** (>1000u): bots favor DMR, BFG
- Bots do **NOT** rocket-launch themselves when an enemy is <160u
  (RateSelf returns -100 for rockets inside 160u)
- Bots use BFG **only** against spawnHealth≥200 enemies

### Console watch

- `Doom Copilot: registered PB3 weapon module in zb_wtypes` at mod load
- `[HL]{"t":"kill",...,"killer":"ZetaDoom"}` lines in data/session_*.log
  prove bots are landing hits

### Calibration — first pass landed 2026-05-19 (CHAT-CC-260519-054)

After each session, run:
```
py -3 brain/calibrate_personas.py
```
Regenerates `brain/calibrated.md` with updated threat weights, weapon
dwell, flee thresholds, and engagement ranges.

**First-pass deltas applied** (49 sessions / 5745 kills / 44 deaths / 707 min):
| Persona | Knob | Seed | Calibrated |
|---|---|---|---|
| Sharpshooter | FleeHpFrac | 0.35 | 0.64 |
| Sharpshooter | EngagementClose/Backoff | 1024/640 | 600/300 |
| Brawler | FleeHpFrac | 0.15 | 0.20 |
| Tank | FleeHpFrac | 0.50 | 0.76 |
| Tank | Sidearm | PB_SMG | PB_Deagle |

Re-run after every meaningful playtest. Empirical signal updates fastest;
hand-tuned design intent stays in the override bodies, the numbers under
the overrides drift with each calibration pass.

### If it fails

- **Bots holding pistol only** → `get zb_wtypes` — should start with `ZetaPB3Weapons;`
- **Bots rocket-suiciding** → close-range RateSelf guard failed; null target?
- **VM crash during combat** → paste stack; likely null target in a Fire()
- **Bots don't kill anything** → damage too low, bump numbers in PB3Weapons.zs

---

## Checkpoint 3.5 — Brawler kite oscillation (2026-05-19)

**Goal:** Confirm the Brawler's time-varying engagement envelope produces
visible dash-in / dash-out motion rather than the prior static plant.

### What to watch

- Brawler should be **continuously moving** during combat. Never reads as
  "stationary, firing." Read as "in, fire, back, fire, in, fire, ..."
- The cycle is ~1.6s end-to-end (~0.8s in / ~0.8s out at 28-tic phases).
  Count Mississippis if it's not obvious.
- Sharpshooter and Tank should NOT kite — they plant at their (now
  calibrated) engagement bands. If you see them oscillating, the kite
  override leaked.

### Trace it (optional)

Open console and:
```
set dc_debug_brawler_kite 1
```
Each oscillation transition emits a `[DC]{"t":"kite_phase",...}` line to
the logfile (`D:\Users\Dan\dev\doom-copilot\data\session_*.log`). Phase 0
= dash-in (Close 120 / Backoff 60), phase 1 = dash-out (Close 600 / Backoff 500).

### Tuning knobs

If the kite feels wrong, the two knobs are in
`copilot-mod/ZScript/PersonaControllers.zs` in `DC_BrawlerController`:
- `KITE_PHASE_TICS` — phase length (28 = ~0.8s; lower = manic, higher = lazier).
- The two dual-band tuples in `EngagementCloseRange()` /
  `EngagementBackoffRange()` — `(120, 60)` for dash-in, `(600, 500)` for
  dash-out. Tighter inner band → harder commit close; wider outer band
  → more dramatic backpedal.

### If it fails

- **Brawler stands still** → `dc_debug_brawler_kite 1` and check the
  logfile. No `kite_phase` events = override isn't binding (check class
  hierarchy). Constant `kite_phase` events but no movement = ZetaBot's
  Subroutine_Attack didn't read the new ranges (rare; would suggest the
  `override double` keyword fell off the wrong end of a refactor).
- **Brawler oscillates but the band feels wrong** → adjust the four
  numbers; re-test.

---

## Checkpoint 4 — Full system playtest

*(Unlocks after Checkpoint 3 passes. Filled in when Item 10 lands.)*
