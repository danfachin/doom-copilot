# WIP Handoff — Four-God Squad build

**Last worked:** 2026-04-20  **Branch:** `four-god-squad`
**Session:** `CODE-CC-260419-010` (single-day span, closed after this handoff)

---

## Current state

Branch sits 16 commits ahead of `master`, all committed cleanly, working
tree clean. Branch has NOT been merged to master — stays on feature
branch until Checkpoint 4 passes and full system is validated.

### What's live and playable right now

Run **[launch/squad_deploy.bat](../launch/squad_deploy.bat)** — full stack:
PB3 + Maps of Chaos + hearth-logger + zetabot-fork + hearth-silencer +
copilot-mod. On MAP01 Nightmare, auto-deploys 3 bots (Sharpshooter /
Tank / Brawler) around the Pilot position 1 second after map load.
Hearth-logger captures telemetry. Hearth-silencer kills PB3's HUD spam.
Bots now recognize PB3 weapons and fire them via `zb_wtypes`-registered
`ZetaPB3Weapons` module.

### Completed roadmap items (10 of 13)

| # | Item | Status |
|---|------|--------|
| 1 | Commit WIP (logger + process_logs + brain harness + annotator) | ✅ |
| 2 | Hearth Silencer PK3 (PB3 HUD message fix) | ✅ |
| 3 | ZetaBot fork at zetabot-fork/ | ✅ **Checkpoint 1 passed** |
| 4 | DoomCopilotController + 4 persona profiles + auto-spawner | ✅ |
| 5 | doom-launcher Squad Deploy preset | ✅ **Checkpoint 2 passed** |
| 6 | ~~VGS audio callouts~~ | SKIPPED (user choice — late-stage polish) |
| 7 | PB3 weapon module (11 classes covering top-12 weapons) | ✅ |
| 8 | Calibration script (telemetry → persona dials) | ✅ |
| — | **Checkpoint 3 — PB3 weapon intelligence playtest** | ⏳ **PENDING** |
| 9 | In-game MENUDEF Squad Deploy menu | — Not started |
| 10 | Claude bridge (gated behind ANTHROPIC_API_KEY) | — Not started |
| — | Checkpoint 4 — full system playtest | — Not reached |
| 11 | ~~Persona voices~~ | SKIPPED |

---

## Picking back up — what next session does

### 1. Run Checkpoint 3 first

Double-click `launch/squad_deploy.bat`. Expected at startup:
- Compile clean (no red ZScript errors)
- Console: `Doom Copilot: registered PB_PlayerPrawn anchor in zb_btypes`
- Console: `Doom Copilot: registered PB3 weapon module in zb_wtypes`
- 1 second after MAP01 loads: 3 bots spawn

During combat, watch for:
- Bots picking up PB3 weapons (not stuck on pistol)
- Range-appropriate weapon choice (shotgun close, DMR mid, BFG on heavies)
- No rocket-suicide (<160u triggers RateSelf = -100)
- `data/session_*.log` capturing `{"t":"kill","killer":"ZetaDoom"}` events

Full pass criteria + failure modes: **[CHECKPOINTS.md § 3](CHECKPOINTS.md)**.

### 2. Then resume: items 9, 10, Checkpoint 4

- **Item 9** (M effort): In-game MENUDEF at main menu for runtime squad
  configuration — persona per slot, map/skill pickers, "Deploy Squad"
  button. Writes to CVars the auto-spawner already reads.
- **Item 10** (M effort): Claude bridge — Python sidecar tailing the
  hearth-logger logfile, calling Claude for tactical callouts, writing
  commands to a bridge CVar that an EventHandler polls. **Gated
  behind `ANTHROPIC_API_KEY` — if env var absent, code path is dead
  (rule engine continues unaffected).** Dan doesn't have an API key
  yet; he runs strategic stuff through Claude Code manually.
- **Checkpoint 4**: full-system playtest, then merge `four-god-squad`
  into `master`.

---

## Known issues / smells to keep an eye on

- **Flank convention bug** flagged in Hearth `system_feedback`: the
  rule-based VGS engine's left/right filters may be inverted vs. the
  logger's angle convention. Not fixed — Dan to pick direction. See
  `brain/vgs_engine.py` lines 353–368 vs. `render_state_for_prompt`
  in `brain/claude_brain.py`.
- **ZetaBot's `zb_btypes` / `zb_wtypes` writes** are injected at
  `OnRegister` from `DC_AutoSpawnHandler`. Both are `server` CVars;
  writes work in single-player but may need revisiting if/when we
  ever test in real co-op multiplayer.
- **ZetaBot bots are `+ISMONSTER +FRIENDLY`**, not real PlayerPawns.
  Per the ZetaBot assessment doc, the cleaner long-term is switching
  the pawn base class to `PlayerPawn` so bots appear as "the fourth
  operator" in scoreboard and don't inflate PB3's kill count. Deferred.
- **Calibration suggests Dan survives combat more cautiously than
  my hand-tuned defaults assumed.** Flee thresholds: my tuning had
  tank=50%, calibration says 78%. Dan can hand-apply from
  `brain/calibrated.md` if playtest shows bots dying too aggressively.
- **Fire() in PB3Weapons.zs uses synthetic hitscan** (ZetaBullet) not
  PB3's real weapon animations. Good enough for bot damage but means
  bot muzzle flashes and recoil don't play. Not a blocker.

## File inventory — what each new piece does

```
doom-copilot/
├── docs/
│   ├── CHECKPOINTS.md            # playtest gate instructions 1-4
│   └── WIP_HANDOFF.md            # this file
├── launch/
│   ├── checkpoint1_isolated.bat  # vanilla Doom + ZetaBot sanity
│   ├── checkpoint1_integration.bat # full stack, 1 bot summon
│   └── squad_deploy.bat          # production Squad Deploy wrapper
├── hearth-silencer/              # PK3 dir — subclasses PB_Hud_ZS
│   ├── ZSCRIPT.zs                #   Hearth_SilentHud class
│   └── MAPINFO.txt               #   StatusBarClass swap
├── logger/
│   ├── hearth-logger/ZSCRIPT.zs  # extended: 9Hz actions, weapon_switch
│   └── process_logs.py           # DATA_DIR fix, regenerated sessions
├── brain/
│   ├── claude_brain.py           # prompt harness (dry-run works, live needs key)
│   ├── vgs_annotator.py          # terminal TUI for manual labeling
│   ├── calibrate_personas.py     # telemetry → dial suggestions
│   ├── calibrated.json/.md       # current generated calibration
│   └── vgs_engine.py             # rule-based engine (pre-existing, unchanged)
├── zetabot-fork/                 # vendored ZetaBot + 3 patches:
│   ├── ZScript.zs                #   line 1113 null-guard, possessed guard
│   │                             #   + virtual on ShouldFollow/Subroutine_Flee/RefreshSkills
│   └── CVarInfo.txt              #   zb_btypes now includes PB_PlayerPrawn
└── copilot-mod/                  # our persona system
    ├── ZSCRIPT.zs                #   include manifest
    ├── MAPINFO.txt               #   registers DC_AutoSpawnHandler
    ├── KeyConf.txt               #   F5-F9 keybinds + F12 disband
    ├── CVARINFO.txt              #   dc_autospawn_squad CVar
    └── ZScript/
        ├── DoomCopilotController.zs   # base w/ virtual hooks
        ├── PersonaControllers.zs      # 4 persona subclasses
        ├── Spawners.zs                # 4 summonable spawners
        ├── AutoSpawner.zs             # EventHandler + zb_btypes/zb_wtypes injection
        └── WeaponModule/
            ├── PB3Weapons.zs          # 11 ZetaWeapon subclasses
            └── ZetaPB3Weapons.zs      # registering module
```

Also edited (outside repo):
- `D:\Users\Dan\dev\doom-launcher\catalog.json` — 3 new mod entries +
  `squad_deploy` profile (no git tracking on launcher side).
