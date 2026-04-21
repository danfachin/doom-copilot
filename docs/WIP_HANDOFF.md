# WIP Handoff — Four-God Squad build

**Last worked:** 2026-04-20  **Branch:** `item9-squad-builder`
**Session:** `DOOM-CC-260420-002` (closed after this handoff)

---

## Current state

Branch sits 9 commits ahead of `four-god-squad` (itself 16 ahead of
`master`). Working tree clean. Branch NOT merged upstream — stays
feature-isolated until Checkpoint 3 passes and Item 9.5 / Item 10
are in a landable shape.

**Net tonight:** the squad survives long enough to actually fight.
Four crash/hang bugs diagnosed and fixed in sequence. Checkpoint 3
still hasn't cleanly passed, but the telemetry is now reliable
enough to debug from.

### What's live and playable right now

`launch/squad_deploy.bat` still deploys the 3-bot squad (Sharpshooter
/ Tank / Brawler) 1 second after MAP01 loads. With tonight's fixes,
survivability is radically improved from the prior session (20s TTL
→ 30+s with bots making kills, Pilot surviving the first room).

### Roadmap status

| # | Item | Status |
|---|------|--------|
| 1–8 | All prior infra | ✅ (unchanged from prior handoff) |
| — | Checkpoint 3 | ⏳ **still pending a clean pass** |
| 9 | In-game MENUDEF Squad Deploy menu | — not started; tonight's work was Item 9's *loadouts + movement*, not the menu itself |
| 10 | Claude bridge (gated on `ANTHROPIC_API_KEY`) | — not started |
| — | Checkpoint 4 | — not reached |

### What tonight actually shipped

New commits on `item9-squad-builder`:

- `65883eb` — Item 9 infra: RPG loadouts (2 primaries + infinite-ammo
  sidearm per persona) + Warhammer-walk movement knobs + safe-spawn
  ring probe.
- `2e24cef` — Item 9 compile fix: `GetClassName()` migration for
  UZDoom 4.14.3 strictness + JIT workaround (inline ring probe,
  explicit `Class<Actor>` local to avoid string→class implicit
  conversion).
- `5eedab4` — `[DC]` telemetry event stream (bot_spawn, state_change,
  bot_hurt, bot_death, bot_tick). Gated by `dc_debug` CVar. Emits
  structured JSON to same logfile as hearth-logger's `[HL]` lines.
- `00c09cb` — Survival pass: FF bug (ZetaBullet species was
  "ZetaBot" vs pawn's "ZetaBotGuy" — broke `+THRUSPECIES`); real
  speed clamp (movement profile now binds `ZetaBotPawn.speedMod`,
  not the ignored `Speed` field); pain-flee transition (PlayPain
  override consults persona flee threshold).
- `635863f` — FF-block at `ZetaBotPawn.DamageMobj` catching
  splash/rocket/plasma from squadmates AND Pilot; persona engagement
  envelopes override hardcoded 256/128 standoff.
- `462ab59` — `PickCommander` override prefers live console player
  over squadmates (bots were commandering each other in a ring);
  `DC_SpawnProbe` +SOLID without +NOBLOCKMAP so TestMobjLocation
  actually sees wall/thing overlap.
- `1d49ac5` — Compile fix: cast both sides to `Actor` for
  `pmo == possessed` check (ZetaBotPawn vs PlayerPawn are sibling
  types, ZScript rejects `==` between them).
- `529a461` — `PickCommander` returns cleanly when no Pilot found
  rather than falling through to vanilla Super (vanilla's random
  squadmate pick could form a 3-bot command ring). Added
  `[DC]pilot_death` marker.
- `bdda366` — **Hard-cap on `Commands()` chain walk (depth=16).**
  Root-cause fix for the final hang. Vanilla's cycle detector only
  caught self-reference (A→A); a 3-bot ring (A→B→C→A) looped
  forever through `RefreshCommander` every tick. The existing
  `depth` parameter was declared but never incremented — dead code.

---

## Picking back up — what next session does

### 1. Re-run Checkpoint 3

Same `squad_deploy.bat`. With the `Commands()` ring-cycle fixed,
the expected failure modes are now:
- Bots dying to real enemies (fine — means FF block works)
- Bots getting stuck geometrically when Pilot moves far (Brawler
  telemetry in session_20260420_220423.log hit a `dist_cmd` of 626
  before disengaging)
- One persona still spawns in wall occasionally (user reported
  after the +NOBLOCKMAP→+SOLID probe fix — **needs verification on
  next playtest**)

Full pass criteria: **[CHECKPOINTS.md § 3](CHECKPOINTS.md)**.

### 2. Session log locations

`data/session_20260420_*.log`. Grep for `[DC]` for squad events,
`[HL]` for Pilot / world events. Latest two (`215736`, `220423`)
both end mid-tic from the hang — the last `[DC]state_change` line
is the final useful signal, not the `tail`.

### 3. Then resume planned item 9.5 + 10

- **Item 9.5 (new)**: altfire support. Persona loadouts declare
  primaries but don't currently wire up alt-fire. Deferred from
  tonight to keep the scope tight while hunting crashes.
- **Item 9 menu**: MENUDEF squad-builder — the original Item 9
  scope, never reached tonight. CVars exist; needs the UI layer.
- **Item 10**: Claude bridge — unchanged from prior handoff.

---

## Known issues / smells

- **Brawler HP-20 plateau** in session_20260420_220423.log: stuck
  at 20 HP for 270+ tics while flipping attacking/wandering without
  taking damage or making progress. Possibly a pathing wedge or a
  "can see enemy, can't reach enemy" oscillation. Not a crash but
  worth watching on next run.
- **Debug-level CVar** `dc_debug=1` is set in the squad_deploy
  preset. Telemetry is valuable right now. Drop to 0 before
  Checkpoint 4 merge — otherwise every session log is 500+ `[DC]`
  lines.
- **`ZetaBot` upstream bugs we've patched locally** (for future
  upstream PR if the author is receptive):
  - `Commands()` cycle detector only catches self-loops (2695).
    Fix: depth cap. Our change is marked with a comment block.
  - `ShouldFollow`, `Subroutine_Flee`, `RefreshSkills`,
    `SetBotState`, `PlayPain`, `PickCommander` were all
    non-`virtual` despite being override-shaped. Now virtual in
    our fork.
  - `ZetaBullet.Species` was `"ZetaBot"` but `ZetaBotPawn.Species`
    is `"ZetaBotGuy"` — `+THRUSPECIES` relies on exact string
    match, so bots shot each other through this typo.
- **`MoveSpeedMult` persona dial was a no-op until tonight.**
  `RealMoveForward` uses hardcoded thrust values; `Speed` actor
  field is ignored. The real lever is `ZetaBotPawn.speedMod` which
  was a `const 1` in the upstream fork. Now a writable `double`
  and `ApplyMovementProfile` binds to it.
- Carries forward from prior handoff: flank bug in VGS engine
  (`system_feedback` ticket), `zb_btypes`/`zb_wtypes` server-CVar
  concerns for real co-op, PlayerPawn base-class switch deferred,
  calibration `brain/calibrated.md` not yet applied to persona
  dials.

## File inventory — new or materially changed this session

Only diffs from prior handoff are listed; everything else stands.

```
copilot-mod/
├── ZScript/
│   ├── DoomCopilotController.zs   # new virtual hooks
│   │                              #   EngagementCloseRange/BackoffRange
│   │                              #   PickCommander override (prefer Pilot, no Super fallback)
│   │                              #   PlayPain flee trigger
│   │                              #   SetBotState telemetry
│   │                              #   spawnTic + [DC]bot_spawn emit
│   ├── PersonaControllers.zs      # new: engagement envelopes per persona,
│   │                              #      MoveSpeedMult/StrafeDamping cut,
│   │                              #      loadout fields (PrimaryClass1/2, Sidearm)
│   ├── AutoSpawner.zs             # safe-spawn ring probe, DC_SpawnProbe
│   │                              #   (+SOLID, no +NOBLOCKMAP)
│   ├── DC_Debug.zs                # NEW — [DC] event handler, dc_debug gate
│   └── WeaponModule/PB3Weapons.zs # GetClassName() migration
├── CVARINFO.txt                   # + dc_debug
├── MAPINFO.txt                    # + DC_DebugHandler event handler
└── ZSCRIPT.zs                     # + DC_Debug.zs include

zetabot-fork/
├── ZScript.zs                     # virtual keywords added on 6 methods;
│                                  # Commands() depth cap (ring-hang fix);
│                                  # Subroutine_Attack now calls
│                                  #   EngagementCloseRange()/BackoffRange()
│                                  #   instead of hardcoded 256/128
└── ZetaCode/
    ├── PawnClasses/ZetaBotPawn.zs # speedMod now writable double;
    │                              # DamageMobj override (FF zero-damage)
    └── WeaponSupport/ZetaBullet.zs # Species "ZetaBot" → "ZetaBotGuy"
```

Launcher side (outside repo): `doom-launcher/catalog.json`
`squad_deploy.extra_args` now includes `+set dc_debug 1`.
