# ZetaBot Assessment -- Doom Copilot Integration

## Executive Summary

ZetaBot is a pure ZScript bot framework for GZDoom that provides a fully functional AI companion/opponent with five behavioral states, a modular weapon system, pathfinding via manually-placed navigation nodes, and a team/order command system. It targets ZScript version 2.5+ and is designed as a drop-in replacement for the legacy ZCajun bot, supporting Doom, Heretic, and Strife out of the box. The codebase is well-structured with clean separation between the controller brain (`ZTBotController`), the physical pawn (`ZetaBotPawn`), and weapon behavior (`ZetaWeapon` / `ZetaWeaponModule`), making it a strong foundation for forking.

For the Doom Copilot project, ZetaBot gives us approximately 70% of what we need for the reflex layer: movement, aiming, weapon firing, target selection, following behavior, and basic team coordination. The main adaptation challenges are (1) building a PB3-specific weapon module that maps to Project Brutality 3's extensive weapon tree with accurate damage/range ratings, (2) replacing the deathmatch-oriented team logic with dedicated co-op companion behavior, (3) integrating the Claude bridge for strategic-layer commands via file-based IPC, and (4) deciding between ZetaBot's node-based pathfinding and ZNav's navmesh approach (or a hybrid).

The architecture is forgiving for our use case. ZetaBot's controller is an Actor that runs `A_ZetaTick()` every frame via a state loop, dispatching to subroutines per FSM state. The weapon module system is explicitly designed for third-party extension -- adding PB3 support means writing a new `ZetaWeaponModule` subclass and corresponding `ZetaWeapon` definitions. The order system already supports "follow me" and "attack that" commands from players, which maps directly to our VGS command surface.


## Architecture Overview

### Controller/Pawn Separation

ZetaBot uses a clean controller/pawn pattern inspired by Unreal Tournament 99's architecture:

- **`ZTBotController`** (`ZScript.zs`, line ~462): The "brain" -- an invisible Actor that runs the AI tick loop. Holds all decision state: current `bstate`, `enemy`, `goingAfter`, `commander`, navigation targets (`navDest`, `currNode`, `currPath`), weapon selection (`loader`, `lastWeap`), aiming (`imprecision`, `angleMomentum`), and skill settings. One controller per bot.

- **`ZetaBotPawn`** (`ZetaCode/PawnClasses/ZetaBotPawn.zs`): The physical body. An `Actor` with `+ISMONSTER`, `+FRIENDLY`, `+SHOOTABLE` flags. Handles sprite states (Stand/Run/Crouch/Pain/Death), movement primitives (`MoveForward()`, `MoveRight()`, `Jump()`), weapon inventory, and collision. The controller calls `possessed.MoveForward()` etc. to move the pawn.

- **`ZetaDoom`** (`ZetaCode/PawnClasses/ZetaDoom.zs`): Game-specific pawn subclass. Defines default inventory (`"Fist,Pistol,Clip"`), sprite frame sets (PLAY), and visual state transitions via `A_SpeedCheck()`.

The controller "possesses" the pawn at spawn via `SetPossessed()`, which sets `possessed.cont = self`. On pawn death, `cont` is nulled and the controller either respawns (deathmatch) or self-destructs.

```
ZTBotController (invisible Actor)
  |-- possessed: ZetaBotPawn (visible Actor, the body)
  |-- loader: ZetaWeaponModule (weapon knowledge)
  |-- currNode: ZTPathNode (current location in nav graph)
  |-- navDest: ZTPathNode (navigation target)
  |-- enemy: Actor (current combat target)
  |-- commander: Actor (who this bot follows/obeys)
  |-- currentOrder: ZTBotOrder (active directive)
```


### The 5-State FSM

```
                    +-----------+
         +--------->| WANDERING |<---------+
         |          +-----+-----+          |
         |                |                |
    (no enemy,       (enemy spotted,  (follow target
     flee done)       PickEnemy())     reached)
         |                |                |
         |                v                |
         |          +-----------+          |
         |          | ATTACKING |          |
         |          +-----+-----+          |
         |                |                |
         |          (lost LOS to           |
         |           enemy)                |
         |                |                |
         |                v                |
   +-----+-----+   +-----------+   +------+-----+
   |  FLEEING   |   |  HUNTING  |   | FOLLOWING  |
   +-----+------+   +-----+-----+   +------+-----+
         ^                |                ^
         |          (regained LOS)         |
         |                |                |
         |                v                |
         |          +-----------+          |
         +----------| ATTACKING |----------+
                    +-----------+
                  (health < 1/7 max      (ShouldFollow()
                   + enemy close)         + commander set)
```

**State enum** (from `ZTBotController`):
```zscript
enum BotState {
    BS_WANDERING = 0,   // Explore, pick nav nodes, auto-use doors
    BS_HUNTING,         // Lost sight of enemy, path to lastEnemyPos
    BS_ATTACKING,       // Has LOS to enemy, fire weapons, strafe
    BS_FOLLOWING,       // Path toward goingAfter (commander/player)
    BS_FLEEING,         // Move away from enemy when health < 1/7
    ORDER_DISBAND       // Special: clear all orders (not a real state)
};
```

**State transitions** are managed by `ConsiderSetBotState()` which respects active orders (e.g., won't wander if ordered to attack) and `SetBotState()` which logs transitions and cleans up `lastEnemyPos`.


### How the Tick Loop Works

The main loop runs via ZScript Actor states:

```zscript
States {
    TickLoop:
        TNT1 A 1 A_ZetaTick;   // Runs every tic (1/35th second)
        Loop;
}
```

`A_ZetaTick()` executes this sequence every tic:

1. **`HealthCheck()`** -- If pawn dead, enter Respawn or Destroy
2. **`StatusDoubleCheck()`** -- Validate team markers, team bounds
3. **`RefreshCommander()`** -- Clear dead/invalid commanders and orders
4. **`RefreshNode()`** -- Find closest visible nav node, auto-plop if needed
5. **`RefreshSkills()`** -- Read `zb_aimstutter`, `zb_turnspeed` CVars
6. **`CrossActivate()`** -- Activate passthrough line specials (teleporters)
7. **`TickAge()`** -- Increment age by 1/35 second
8. **`ApplyMovement()`** -- Apply angular momentum, execute pawn movement
9. **Think gate** (`TickToThink()`) -- Only runs AI logic every 4th tic (`thinkTimer = 3`)
10. **`RefreshEnemy()`** -- Clear dead enemies
11. **`TryUse()`** -- Auto-use doors/switches
12. **`GiveCommands()`** -- Issue orders to nearby friendly bots
13. **`DispatchAiState()`** -- Call appropriate `Subroutine_*` for current `bstate`
14. **`PickEnemy()`** -- Scan for visible enemies (if not already attacking/fleeing)
15. **`FireAtBarrels()`** -- Opportunistic barrel shooting

The think gate is notable: movement/aiming runs every tic (35 Hz), but AI decisions run at ~8.75 Hz (every 4th tic). This is a sensible performance optimization.


## What We Reuse As-Is

### 1. Controller/Pawn Architecture
The `ZTBotController` / `ZetaBotPawn` separation maps perfectly to our reflex-layer / strategic-layer split. The controller already manages all the state we need. No structural changes required.

### 2. Core Movement System
`ZetaBotPawn`'s movement primitives are solid:
- `MoveForward()`, `MoveBackward()`, `StepBackward()`, `MoveRight()`, `MoveLeft()` with momentum-based smoothing
- `MovementModifier` enum: `MM_None`, `MM_Run`, `MM_Crouch`
- `Jump()` with `sv_allowjump` checking
- `CapSpeed()` velocity limiting
- `ApplyMovement()` with friction-based deceleration (`forward /= 1.5`)

### 3. Aiming System
The aiming system includes skill-scaled imprecision:
- `aimToward(Actor other, double speed, double threshold)` -- Smooth interpolation toward target
- `aimAtAngle(double angle, double speed, double randRange)` -- With configurable scatter based on `imprecision` CVar
- `angleMomentum` -- Inertial aiming that prevents robotic snapping
- `LineOfSight()` -- Cone-based visibility check (dot product + `CheckSight`)

### 4. Obstruction Handling
`CheckObstructions()` uses three LineTraces (front, left-60, right+60) to detect walls and auto-navigate. `CheckBlocked()` detects stuck states via `blockingMobj`/`blockingLine` and applies random strafe/rotation to unstick.

### 5. Target Priority System
```zscript
double targetPriority(Actor other) {
    double res = possessed.Distance3D(other) / other.Health;
    if (other.CheckClass('PlayerPawn'))
        res /= 1.5;
    return res;
}
```
Simple but functional: prioritizes close, low-health, player-type targets. We extend this rather than replace it.

### 6. Respawn System
Fully functional deathmatch respawn: finds valid `NT_RESPAWN` nodes, telefrags overlaps, resets all state. Works for co-op respawn with `zb_alsocooprespawn` CVar.

### 7. Debug Logging Infrastructure
The `mixin class DebugLog` system with `LT_ERROR/WARNING/INFO/VERBOSE` levels controlled by `zb_debug` CVar. Invaluable for development -- we keep this and extend it with AAR data collection hooks.

### 8. Team Color / Marker System
`ZetaTeamMarker` for visual identification, 8-team color palette, `IsSameTeam()` checks. Works for identifying bot as player's companion.


## What We Modify

### 1. Weapon Module System -- PB3 Module Required

**Current state:** `ZetaDoomWeapons` module registers 9 vanilla Doom weapons. Each `ZetaWeapon` subclass defines:
- `FireInterval` / `AltFireInterval` (in 1/10,000,000 second units -- unusual but functional)
- `MinAmmo` / `AltMinAmmo` / `AmmoType` / `AltAmmoType`
- `RateSelf(Actor shooter, Actor target)` -- Returns a rating based on distance
- `Fire()` / `AltFire()` -- Actually fires the weapon (spawns projectiles or hitscans)

**Example -- Rocket Launcher rating:**
```zscript
override double RateSelf(Actor shooter, Actor target) {
    if (shooter.Distance3D(target) < 128)
        return -50;   // Too close! Splash danger!
    return 2000 / (1 + sqrt(shooter.Distance2D(target) * 1.6));
}
```

**What changes for PB3:**
- New `ZetaPB3Weapons : ZetaWeaponModule` with all PB3 weapons registered
- Each PB3 weapon needs a `ZetaWeapon` subclass with accurate damage curves
- PB3 weapons use different actor class names (not `"Shotgun"`, `"RocketLauncher"`, etc.)
- PB3 has weapon tiers, alternate fire modes, and tactical reloads that need representation
- The `ZTMyWeapon` convenience class handles hitscan/projectile/melee/splash classification -- this maps well to PB3's weapon taxonomy
- The `IsPickupOf(Weapon other)` override needs PB3 class name matching

**Key concern:** PB3 weapon class names are not publicly documented. We will need to inspect PB3's ZScript/DECORATE to extract actor class names, damage values, and ammo types. This is the single largest unknown in the integration.

### 2. Following / Co-op Behavior

**Current state:** `Subroutine_Follow()` paths toward `goingAfter` (set by order or commander auto-pick). Follow distance: starts following when `Distance3D > 300`, stops when `Distance3D < 60`. Uses `PathMoveTo()` for navigation.

**What changes:**
- **Follow distance tuning:** 300 units is too far for a combat companion. We want tighter formation (150-200 units) with dynamic adjustment based on combat state.
- **Formation awareness:** Current following is single-point. We need offset following (don't stack on the player, stay to a side).
- **Combat following:** Bot should not blindly follow into danger. When following + enemies spotted, it should take cover near the player rather than pathfinding directly to them.
- **VGS integration point:** "Follow me", "Hold position", "Go there" commands map to existing `ZTBotOrder` types but need smoother transitions.

### 3. Target Selection / Threat Scoring

**Current state:** `PickEnemy()` scans all visible enemies via `ThinkerIterator`, sorts by `targetPriority()` (distance / health, with player bonus). `VisibleEnemies()` checks `bISMONSTER`, `Health > 0`, `!bInvisible`, `CheckSight`, `IsEnemy`.

**What changes for PB3:**
- PB3 monsters have vastly different threat levels. A Baron of Hell matters more than an Imp regardless of distance.
- Need a threat classification table mapping PB3 monster classes to danger ratings
- Should factor in monster attack types (hitscan enemies are higher priority than melee)
- Environmental awareness: monsters near the player should be prioritized over those near the bot
- The `isEnemy()` function needs updating -- in co-op, `bFRIENDLY` logic is simpler (everything not-player is enemy), but PB3 may have friendly NPCs

### 4. Order / Command System

**Current state:** `ZTBotOrder` supports 6 order types (wander, hunt, attack, follow, flee, disband). Orders are issued via `ZTBotOrderCode` actors spawned by keybinds. The system uses `Commands()` to check chain-of-command (prevents circular orders).

**What changes:**
- Strip the deathmatch team-order logic (we're always co-op)
- Map VGS callouts to orders: "Attack!" -> `BS_ATTACKING` with LookAt target, "Fall back!" -> `BS_FLEEING`, "Follow me!" -> `BS_FOLLOWING` with player as target
- Add new order types: "Hold position" (stay at current node), "Defend area" (wander within radius)
- The Claude bridge writes orders to a file; a new `ClaudeBridgeReader` thinker polls the file and translates to `ZTBotOrder` instances

### 5. Fleeing Behavior

**Current state:** `Subroutine_Flee()` is extremely simple -- moves away from enemy if health < 1/7 max and enemy is within 1024 units, otherwise immediately transitions back to wandering. This is nearly useless.

**What changes:**
- Flee to health pickups (requires item awareness -- scan for `HealthBonus`, `Medikit`, etc.)
- Flee to player (companion should retreat toward the player, not randomly away)
- Configurable flee threshold (1/7 max health is very aggressive -- PB3 enemies hit harder)
- Health item memory: remember where health packs were seen, path to them when low

### 6. Bot Chat -> VGS Callout System

**Current state:** `BotChat(String kind, double importance)` plays sound files from `"zetabot/{voice}/{kind}"`. Kinds: `IDLE`, `HURT`, `TARG`, `ACTV`, `ELIM`, `ORDR`, `COMM`. Importance is a probability threshold.

**What changes:**
- Replace random voice barks with structured VGS callouts
- "Enemy spotted!" when entering `BS_ATTACKING`
- "I need health!" when entering `BS_FLEEING`
- "Target down!" on kill
- "Following!" when ordered
- These callouts also write to the AAR data file for Claude's strategic layer


## What We Build New

### 1. Claude Bridge (File-Based IPC)

ZScript cannot do network I/O or file I/O at runtime. The bridge uses a polling mechanism:

```
Claude (Python)                    GZDoom (ZScript)
    |                                    |
    |-- writes command.json -->          |
    |                           ClaudeBridgeThinker
    |                           reads CVAR "dc_command"
    |                           (set by external tool)
    |                                    |
    |                           Translates to ZTBotOrder
    |                                    |
    |                           Bot executes order
    |                                    |
    |                           Bot writes state to
    |                           CVAR "dc_state"
    |                                    |
    |   <-- reads state CVAR -----------|
```

**Implementation approach:** GZDoom supports reading/writing CVars from external tools via NETEVENT or the console. A Python process can inject console commands via a named pipe, stdin, or the GZDoom remote console API. The bot exposes its state (health, ammo, position, current target, bstate) as a serialized string CVar. Claude reads this at ~1 Hz and writes strategic commands.

**New ZScript classes needed:**
- `DoomCopilotController : ZTBotController` -- Extended controller with Claude bridge hooks
- `ClaudeBridgeThinker : Thinker` -- Polls command CVar, translates to orders
- `StateReporter : Thinker` -- Serializes bot state to CVar each second

### 2. VGS Callout System

A structured communication system replacing random barks:

```zscript
class VGSCallout : Thinker {
    enum CalloutType {
        VGS_ENEMY_SPOTTED,     // "Contact!"
        VGS_NEED_HEALTH,       // "I need healing!"
        VGS_NEED_AMMO,         // "I need ammo!"
        VGS_TARGET_DOWN,       // "Target eliminated!"
        VGS_FOLLOWING,         // "On your six!"
        VGS_HOLDING,           // "Holding position!"
        VGS_RETREATING,        // "Falling back!"
        VGS_AREA_CLEAR,        // "Area clear!"
        VGS_HEAVY_INCOMING,    // "Heavy enemy incoming!"
        VGS_LOW_HEALTH,        // "I'm hurt bad!"
    };
}
```

Each callout plays an audio cue, displays HUD text, and writes to the AAR log.

### 3. PB3 Weapon Module

The largest new code component. Requires:

1. **PB3 weapon class audit** -- Extract all weapon actor names from PB3's ZScript/DECORATE
2. **ZetaPB3Weapons : ZetaWeaponModule** -- Registration of all PB3 weapons
3. **Per-weapon ZetaWeapon subclasses** with accurate:
   - `RateSelf()` curves using actual PB3 damage values
   - `Fire()` / `AltFire()` that invoke the correct attack
   - Ammo type mapping
   - Splash danger radius for explosives
   - Melee range flags
4. **Weapon tier awareness** -- PB3 has weapon upgrade paths; bot should prefer upgraded variants

### 4. AAR Data Collection Hooks

After-Action Review data for Claude's strategic layer:

```zscript
class AARCollector : Thinker {
    // Logged per-encounter:
    // - Timestamp, bot health at engage/disengage
    // - Weapon used, shots fired, hits landed
    // - Enemy type, enemy health
    // - Distance at engagement
    // - State transitions during encounter
    // - Death cause (if bot died)
    // - Ammo expenditure
    // - Time spent in each bstate
}
```

Data serialized to CVar or written to a log file via ACS `PrintBold` redirect.


## Navigation: ZetaBot Nodes vs ZNav Navmesh

### ZetaBot Node System

**How it works:** `ZTPathNode` actors are placed in the level (manually or auto-generated). Each node has a `NavigationType` (13 types: Normal, Use, Slow, Crouch, Jump, Avoid, Candy, Shoot, Respawn, Teleport Source, Block, etc.). Nodes connect to neighbors via line-of-sight within range. Pathfinding uses A* over the node graph via a custom `PriorityQueue` (binary heap implementation in `Pathing.zs`).

**Node connection logic:** `canConnect(node)` checks distance (within CVar `zb_noderange`, default ~512 units), line-of-sight (`CheckSight`), and height difference. `postCanConnect()` filters out redundant connections. Connections are computed dynamically at query time -- **there is no precomputed adjacency graph**.

**Node format:** Serialized as `MAP01::x,y,z,type,useDir,assocId:x,y,z,...::` strings stored in CVars or lump files. Example from `nodes/Doom2_MAP01.txt`:
```
MAP01::-72,900,8,0,0:-73,1285,56,0,0:-35,1573,56,2,0:...
```

**Auto-node generation:** When `zb_autonodes` is enabled, the bot auto-plops nodes at regular intervals as it explores:
- `zb_autonodenormal` -- Normal navigation nodes
- `zb_autonodeuse` -- Use/door nodes when activating lines
- `zb_autonodetele` -- Teleport source/destination pairs
This means the bot learns the map as it plays. Clever, but slow to build coverage.

**A* implementation:** Custom priority queue (`PriorityQueue` class) with binary heap. The `findPathTo()` method on `ZTPathNode` runs A* from the current node to the goal node. Cost function includes `SpecialCost()` for node types (Avoid = +1024, Candy = -1024, Teleport = distance bonus, height penalty).

**Performance characteristics:**
- Neighbor lookup: O(N) per node (iterates ALL nodes via `ThinkerIterator` to find neighbors)
- A* per path: O(N * log(N)) where N = total nodes in level
- This is the main bottleneck -- large maps with many nodes will be slow

### ZNav Navmesh System

**How it works:** ZNav (`zdoom-pathfinding`) uses pre-generated triangle-mesh navigation data. A separate tool ([zdoom-navmesh-generator](https://github.com/disasteroftheuniverse/zdoom-navmesh-generator)) reads the TEXTMAP lump, builds a 3D model, feeds it to Recast (the industry-standard navmesh generator), and outputs JSON stored in `MODELS/NAV/mapname.json`.

**Architecture:**
- `ZNavHandler : StaticEventHandler` -- Detects navmesh files on level load, creates `ZNavThinker`
- `ZNavThinker` -- Parses JSON, manages `ZNavMesh`, tracks agents
- `ZNavMesh` -- Contains all nodes, groups, spatial grid cells, pathfinding methods
- `ZNavNode` -- Polygon (triangle) with centroid, vertices, neighbor IDs, portals
- `ZNavGroup` -- Connected component (islands of walkable area)
- `ZNavAgent : Actor` -- Base class for navigating actors, handles route following
- `ZNavAStar` -- Standard A* over polygon graph using `ZNavBinaryHeap`
- `ZNavChannel` -- Funnel algorithm for path smoothing (produces clean curves, not jagged node-to-node paths)

**Spatial partitioning:** Grid-based cell system (`ZNavCell`) similar to Doom's blockmap. Nodes and agents are assigned to cells for O(1) spatial lookups instead of scanning all nodes.

**Path quality:** The funnel/string-pull algorithm produces smooth paths that hug corners naturally. ZetaBot's node paths are jagged -- the bot walks node-to-node in straight lines.

**A* implementation:** Standard textbook A* with binary heap open set. Heuristic is `Math.CheapDistance()` (likely Manhattan or Chebyshev). Node cost defaults to 1, modified by cell agent density (crowd avoidance).

### Comparison

| Aspect | ZetaBot Nodes | ZNav Navmesh |
|--------|--------------|--------------|
| Setup cost per map | Manual node placement or auto-generate at runtime | Pre-generate with external tool |
| Path quality | Jagged (node-to-node) | Smooth (funnel algorithm) |
| Neighbor lookup | O(N) -- ThinkerIterator scan | O(1) -- precomputed adjacency |
| Spatial query | O(N) | O(1) -- grid cells |
| Height handling | Z-coordinate in nodes | 3D polygon mesh |
| Door/switch support | Native (NT_USE nodes) | Not built-in |
| Jump/crouch support | Native (NT_JUMP, NT_CROUCH nodes) | Not built-in |
| Teleporter support | Native (NT_TELEPORT_SOURCE) | Not built-in |
| PB3 map support | Works on any map (auto-nodes) | Needs per-map mesh generation |
| Runtime overhead | Low (few nodes) to High (many nodes) | Low (precomputed) |

### Recommendation: Hybrid Approach

**Start with ZetaBot nodes for Phase 1-2.** The auto-node system means we can play any PB3 map immediately without pre-generation. Door, jump, crouch, and teleporter node types are critical for PB3 maps and are built into ZetaBot's system.

**Migrate to ZNav for Phase 3** when we need high-quality tactical movement. The funnel algorithm produces realistic pathing that looks natural in co-op. The spatial partitioning eliminates the O(N) neighbor scan bottleneck.

**Hybrid integration plan:**
1. Keep ZetaBot's `ZTPathNode` types for special actions (Use, Jump, Crouch, Teleport, Shoot)
2. Use ZNav navmesh for general traversal between special nodes
3. When a ZNav path passes near a ZTPathNode, inject the special action
4. This gives us smooth movement AND door/switch/jump awareness

**The practical problem:** ZNav requires running the navmesh generator tool on every map. PB3 custom maps won't have meshes. The ZetaBot auto-node system handles this gracefully by learning as the bot explores. For "just works" behavior, we need auto-nodes as a fallback. This is also why Phase 1 uses ZetaBot nodes exclusively -- it removes an entire tooling dependency from first playtest.


## Integration Plan

### Phase 1: Basic Companion (Follow + Shoot)

**Goal:** Bot follows the player, shoots enemies, doesn't die immediately. Playable in vanilla Doom or PB3 lite mode.

**Steps:**
1. Fork ZetaBot repo into `doom-copilot/zetabot-fork/`
2. Create `DoomCopilotPawn : ZetaDoom` with companion-appropriate defaults
   - `bFRIENDLY = true` always (no deathmatch toggle)
   - Default follow distance reduced to 200 units
   - Companion name set via CVar `dc_name`
3. Create `DoomCopilotController : ZTBotController`
   - Override `BeginPlay()` -- always set `commander = player`, `bstate = BS_FOLLOWING`
   - Override `Subroutine_Follow()` -- tighter follow distance, stay to player's right flank
   - Override `PickEnemy()` -- prioritize enemies attacking the player
   - Override `Subroutine_Attack()` -- return to following after engagement ends
   - Remove deathmatch logic (frag counting, team assignment for DM)
4. Strip `ZTBotOrderCode` spawner system -- replace with direct function calls from VGS
5. Test with vanilla Doom weapons (existing `ZetaDoomWeapons` module)
6. Add basic VGS callouts: "Contact!", "Target down!", "Following!"

**Deliverable:** A bot that follows the player through any Doom map, engages enemies, and returns to following. Controllable with "Follow me" / "Hold position" / "Attack" keybinds.

### Phase 2: PB3-Aware Combat (Weapon Selection, Threat Priority)

**Goal:** Bot understands PB3 weapons and monsters, makes intelligent weapon choices, prioritizes threats appropriately.

**Steps:**
1. Audit PB3 weapon classes -- extract all actor names, damage values, ammo types from PB3 ZScript
2. Build `ZetaPB3Weapons : ZetaWeaponModule` registering all PB3 weapons
3. Build per-weapon `ZetaWeapon` subclasses with accurate `RateSelf()` curves
   - Melee weapons: high rating at close range only
   - Shotguns: peak at 128-384 units, falloff beyond
   - Rifles: flat rating curve, good at all ranges
   - Explosives: negative rating below splash radius, peak at medium range
   - BFG-class: highest rating but only when multiple enemies visible
4. Build PB3 threat classification table:
   ```
   Cyberdemon/Spider Mastermind -> THREAT_EXTREME (5.0x priority)
   Baron/Hell Knight -> THREAT_HIGH (3.0x)
   Revenant/Mancubus/Arachnotron -> THREAT_MEDIUM_HIGH (2.5x)
   Chaingunner/Archvile -> THREAT_PRIORITY_HITSCAN (4.0x -- always prioritize hitscan)
   Imp/Demon/Spectre -> THREAT_MEDIUM (1.5x)
   Zombie/Shotgunner -> THREAT_LOW (1.0x)
   ```
5. Override `targetPriority()` with threat-class-aware scoring
6. Add ammo awareness to weapon selection -- don't waste rockets on zombies
7. Implement health-item seeking for flee behavior
8. Add PB3-specific features: recognize PB3 special pickups, handle PB3 alt-fire modes

**Deliverable:** Bot makes smart weapon choices (SSG for close Barons, chaingun for distant Chaingunners, rockets for groups) and prioritizes dangerous enemies.

### Phase 3: Claude-Directed Tactics (VGS Commands Modify Behavior)

**Goal:** Claude's strategic layer can observe bot state and issue tactical directives that modify reflex-layer behavior.

**Steps:**
1. Build `StateReporter` thinker -- serializes to CVar every 35 tics (1 second):
   ```
   dc_state = "HP:67|ARM:42|AMMO:SHL:24,RKT:8,CEL:120|POS:1024,2048,0|STATE:ATTACK|
               ENEMY:Baron:HP:340:DIST:256|KILLS:12|DEATHS:1|TIME:245"
   ```
2. Build `ClaudeBridgeThinker` -- reads `dc_command` CVar:
   ```
   dc_command = "FOLLOW|AGGRESSIVE"    // Follow but engage freely
   dc_command = "HOLD|1024,2048"       // Hold position at coordinates
   dc_command = "PUSH|NORTH"           // Advance in direction
   dc_command = "RETREAT"              // Fall back to player
   dc_command = "CONSERVE_AMMO"        // Prefer melee/pistol, save heavy ammo
   dc_command = "PRIORITY|Archvile"    // Always target this enemy type first
   ```
3. Build Python-side Claude bridge:
   - Reads `dc_state` via GZDoom console log parsing or NETEVENT
   - Feeds state + recent AAR data to Claude
   - Claude generates tactical command
   - Writes to `dc_command` via console injection
4. Implement AAR collection:
   - Per-encounter logs (weapon used, damage dealt/taken, outcome)
   - Death analysis (what killed the bot, could it have been avoided)
   - Ammo efficiency tracking
   - Map progression tracking (areas cleared, areas remaining)
5. Tactical behavior modifiers:
   - `AGGRESSIVE` -- Reduce follow distance, increase engagement range
   - `DEFENSIVE` -- Increase follow distance, flee earlier
   - `CONSERVE_AMMO` -- Weapon rating modifier that penalizes heavy ammo
   - `PRIORITY_TARGET` -- Override target selection to focus specific enemy class
6. VGS command integration -- Player keybinds that also feed into Claude's context:
   - "Attack!" (player points at target, bot gets `BS_ATTACKING` order)
   - "Defend here!" (bot enters hold-position mode at current location)
   - "Need backup!" (bot immediately paths to player, enters defensive formation)

**Deliverable:** A bot that receives and executes strategic commands from Claude, adapts its behavior based on tactical context, and generates useful telemetry for after-action review.


## Risk Assessment

### Compatibility with PB3

**ZScript version:** ZetaBot targets `version "2.5"` (GZDoom 3.3+). PB3 likely requires GZDoom 4.x+. We should bump to `version "4.0"` or higher to access newer ZScript features (better array handling, null coalescing).

**Actor conflicts:** ZetaBot spawns its own pawn actors (`ZetaDoom`, `ZetaHeretic`, etc.) that are `+ISMONSTER +FRIENDLY`. PB3 may have systems that target all monsters or all friendly actors with AoE effects, buffs, or killcount tracking. The bot pawn may:
- Get counted in PB3's kill percentage
- Receive PB3 player buffs (potentially beneficial)
- Trigger PB3 monster-targeting scripts
- Conflict with PB3's weapon-give systems

**Weapon inventory:** ZetaBot gives weapons via `GiveInventoryType()` on the pawn. PB3 weapons may require special initialization that a simple inventory give doesn't trigger.

**Mitigation:** Test with PB3 3.0 stable. If actor conflicts are severe, change pawn base class to `PlayerPawn` (impersonating a player) instead of monster. This is a bigger change but eliminates friendly-monster edge cases.

### Performance Concerns

**ThinkerIterator scans:** ZetaBot uses `ThinkerIterator.Create("Actor", STAT_DEFAULT)` in several hot paths:
- `VisibleEnemies()` -- Scans ALL actors in the level every 4 tics
- `VisibleFriends()` -- Same
- `NeighborsOutward()` -- Scans ALL ZTPathNodes for every neighbor lookup during A*
- `ClosestNode()` / `ClosestVisibleNode()` -- Scans ALL ZTPathNodes

On large PB3 maps with 500+ monsters and 200+ nodes, these O(N) scans per bot per tick add up.

**A* on large maps:** The `findPathTo()` implementation uses O(N * log(N)) A* but with O(N) neighbor discovery at each step (not precomputed adjacency). On a 200-node map, this means ~200 ThinkerIterator scans per A* invocation. Each scan touches every node.

**Mitigation strategies:**
- Cache neighbor lists on nodes (compute once, invalidate on node add/remove)
- Reduce `VisibleEnemies` scan frequency (every 8 tics instead of 4)
- Use sector-based spatial partitioning for enemy scanning
- Limit pathfinding to one A* per 10 tics with caching
- If migrating to ZNav: all of these problems go away (precomputed adjacency, grid cells)

### Mod Load Order Issues

GZDoom loads PK3s in command-line order. ZetaBot must load AFTER PB3 to:
- See PB3 weapon classes for `IsPickupOf()` matching
- Access PB3 monster classes for threat classification
- Override any PB3 systems that affect friendly actors

**Load order:** `gzdoom -iwad doom2.wad -file pb3.pk3 doom-copilot.pk3`

If PB3 uses `replaces` directives on base Doom actors, ZetaBot's vanilla weapon module will break (e.g., `ZetaShotgun.IsPickupOf()` checks `other.GetClass() == "Shotgun"` but PB3 replaces `Shotgun` with `PB_Shotgun`). The PB3 weapon module must use PB3's actual class names.

### Single-Player Co-op Limitation

ZetaBot was designed for multiplayer (deathmatch + co-op with multiple players). In single-player with a bot companion, some assumptions break:
- Fraglimit/timelimit logic is irrelevant (strip it)
- `playeringame[]` array may only have one entry
- The bot pawn is NOT in `players[]` -- it's a monster-flagged actor
- PB3 systems that check `PlayerCount()` will see 1 player

**Mitigation:** These are cleanup tasks, not blockers. The core AI (follow, attack, hunt, flee) works fine in single-player context.

### Auto-Node Reliability

ZetaBot's auto-node system (`zb_autonodes`) is the bot's fallback for unmapped maps. It works by plopping nodes as the bot explores. However:
- The bot must actually visit an area before it can path through it
- In co-op, the bot follows the player, so it only generates nodes on the player's path
- Backtracking to missed areas won't have node coverage
- Complex multi-level maps (elevators, rising stairs) may not generate correct height nodes

**Mitigation:** For key PB3 maps, pre-generate node files. For random maps, accept that the bot will occasionally get lost. The fallback behavior (random movement when no path) is functional if ungraceful.
