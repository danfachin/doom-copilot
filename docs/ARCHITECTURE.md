# Doom Copilot Architecture

## System Overview

Doom Copilot is an AI co-op companion for Doom running Project Brutality 3. It plays
alongside a human as a second player -- covering flanks, calling out threats, managing
its own weapon loadout, and making tactical decisions about when to push or fall back.

The core design problem: LLMs are smart enough to make good tactical decisions, but far
too slow to play an FPS. Claude API responses take 1-3 seconds. Doom runs at 35 tics
per second. A bot that waits for an API call before dodging a fireball is a dead bot.

The solution is a **two-layer architecture**:

```
 Layer 2: Strategic Brain (Claude API, ~1 Hz)
    "We should retreat -- too many heavies, low on health"

 Layer 1: Reflex Bot (ZScript, 35 Hz)
    "Dodge left, shoot Revenant, pick up medkit"
```

Layer 1 handles everything that needs to happen NOW -- movement, aiming, dodging,
target selection, weapon switching. It runs as a ZScript mod inside GZDoom at native
tick rate.

Layer 2 handles everything that benefits from reasoning -- should we push or hold?
Is this the right time to use the BFG? Should we retreat to find health? It runs as
an external Python process that sends game state to Claude and relays decisions back
to the bot.

The two layers communicate through a shared file on disk. This is deliberately simple.
No sockets, no IPC, no message queues. The bot reads a file. Claude writes to it.
It works.

---

## Layer 1: ZScript Reflex Bot

### Foundation

The reflex bot is based on [ZetaBot](https://forum.zdoom.org/), adapted for Project
Brutality 3's expanded enemy and weapon roster. ZetaBot provides solid pathfinding,
basic combat AI, and GZDoom integration. Our modifications add PB3 awareness, the
command interface, and threat prioritization.

### Execution

- Runs inside GZDoom as a loaded mod (`.pk3`)
- Native 35 Hz tick rate -- same as the game engine
- Full access to the game world: actor positions, health values, line-of-sight checks
- Controls a player-class actor (joins as Player 2 in co-op)

### FSM States

The bot operates as a finite state machine with four states:

```
                    +-----------+
          +-------->|  FOLLOW   |<--------+
          |         +-----------+         |
          |           |       |           |
     no targets    target   command     timeout
          |         seen    received      |
          |           |       |           |
          v           v       v           v
      +-----------+ +-----------+ +-----------+
      |   HOLD    | |  ATTACK   | |   FLEE    |
      +-----------+ +-----------+ +-----------+
```

- **Follow** (default) -- Trail the human player at a configurable distance. Scan for
  targets. Transition to Attack on enemy contact.
- **Attack** -- Engage the highest-priority target. Select optimal weapon. Manage
  distance based on weapon type (close for SSG, far for rockets). Return to Follow
  when all targets are dead.
- **Flee** -- Retreat toward the human player or toward known health pickups. Triggered
  when HP drops below a survival threshold or when Claude issues a retreat command.
- **Hold** -- Stay at current position and engage anything in range. Used for defensive
  setups (holding a chokepoint, guarding a flank).

### PB3 Weapon Selection

Project Brutality 3 has dozens of weapons with different damage types, projectile
speeds, and splash radii. The bot selects weapons based on a scoring function:

```
score = base_damage * type_multiplier / distance_penalty
```

Where:
- `base_damage` comes from the PB3 weapon database (extracted from source)
- `type_multiplier` accounts for enemy resistances (e.g., don't use fire on fire-immune)
- `distance_penalty` penalizes projectile weapons at close range (self-damage) and
  hitscan weapons at extreme range (spread)

The bot prefers overkill-efficient choices -- it won't waste a BFG shot on an Imp.

### Threat Prioritization

When multiple enemies are visible, the bot scores each one:

```
threat = (tier_weight * tier) + (distance_weight / distance) + (angle_weight * facing_player)
```

Key factors:
- **Tier** -- An Archvile is always more dangerous than a Zombie. PB3 tiers range from
  T1 (fodder) to T5 (boss).
- **Distance** -- Closer enemies score higher.
- **Facing the player** -- An enemy aiming at the human player gets a massive boost.
  The bot prioritizes threats TO ITS PARTNER, not just to itself.
- **Behavior state** -- An enemy mid-attack-animation scores higher than one wandering.

---

## Layer 2: Claude Strategic Brain

### Overview

The strategic brain is a Python process that runs alongside GZDoom. It reads game
telemetry, builds a state snapshot, sends it to the Claude API, and writes Claude's
response back to a command file that the ZScript bot reads.

### Process Loop

```python
while running:
    state = read_telemetry()          # Parse latest game state from logfile
    if state.changed_significantly():  # Don't spam the API with identical states
        response = claude.complete(    # Send state snapshot to Claude
            system=TACTICAL_PROMPT,
            messages=build_context(state, recent_history)
        )
        command = parse_response(response)
        write_command_file(command)    # Bot picks this up next tick
    sleep(0.5)                         # ~1-2 Hz update rate
```

### State Snapshot

Each snapshot sent to Claude includes:

- Player HP, armor, ammo counts
- Bot HP, armor, ammo counts
- Visible enemies (type, distance, direction, health %)
- Recent kills and damage events (last 10 seconds)
- Current map area (sector/room identifier)
- Bot's current FSM state
- Active VGS callouts (what's been said recently)

### Claude's Response

Claude returns a structured response:

```json
{
  "vgs": "VEH",
  "command": "attack_target",
  "target_class": "Archvile",
  "reasoning": "Archvile is resurrecting dead enemies behind the horde"
}
```

The `reasoning` field is logged for After Action Reports but not sent to the bot.
The bot only receives the command and optional target.

### Tactical Prompt

The system prompt gives Claude the role of a co-op partner. It includes:

- The full VGS command vocabulary
- The PB3 enemy database (tiers, threats, weaknesses)
- Rules of engagement (when to retreat, when to push, when to save power weapons)
- The current mission context (map name, difficulty, objectives found)

Claude is instructed to think like an experienced Doom player, not a cautious AI.
Aggression is usually correct in PB3.

---

## Telemetry System

### Data Collection

A ZScript `EventHandler` hooks into GZDoom's event system and logs structured data
to the console:

```
[HEARTH_TEL] STATE|tick=12450|hp=85|armor=40|ammo_clip=24|ammo_shell=16|...
[HEARTH_TEL] ENEMY|tick=12450|class=Revenant|dist=384|angle=45|hp=80|state=missile
[HEARTH_TEL] KILL|tick=12460|class=Revenant|weapon=SSG|distance=256
[HEARTH_TEL] DAMAGE|tick=12455|amount=25|source=Revenant|type=missile
[HEARTH_TEL] DEATH|tick=12500|killer=Archvile|weapon=fire
[HEARTH_TEL] MAP|event=enter|map=MAP07|title=Dead Simple|time=0
```

### Log Capture

GZDoom's `-logfile` launch parameter writes all console output to disk. The Python
bridge tails this file in real-time, filtering for `[HEARTH_TEL]` lines.

```
gzdoom.exe -file brutality.pk3 copilot.pk3 -logfile telemetry.log
```

### Post-Processing

After a session ends, a post-processor converts the raw log into:

- **Per-map JSONL** -- One JSON object per event, organized by map. Used for After
  Action Reports and statistical analysis.
- **Session summary** -- Aggregate stats (total kills, deaths, damage dealt/taken,
  weapon usage, map completion times).
- **Timeline** -- Ordered event sequence for replay analysis.

---

## PB3 Knowledge Base

### Enemy Database

Every PB3 monster is cataloged with combat-relevant data:

| Field          | Example (Archvile)                     |
|----------------|----------------------------------------|
| Class name     | `PB_Archvile`                          |
| Display name   | Archvile                               |
| HP             | 700                                    |
| Tier           | T4                                     |
| Speed          | Fast                                   |
| Attack type    | Fire (hitscan, area)                   |
| Resurrects     | Yes                                    |
| Resistances    | Fire immune                            |
| Threat notes   | Priority kill. Resurrects dead enemies |

### Weapon Database

PB3 weapon data is extracted from the mod's DECORATE/ZScript source:

| Field          | Example (Super Shotgun)           |
|----------------|-----------------------------------|
| Class name     | `PB_SuperShotgun`                 |
| Slot           | 3                                 |
| Damage/shot    | 10 * 20 pellets = 200             |
| Damage type    | Ballistic                         |
| Effective range| Close (< 512 units)              |
| Ammo type      | Shell                             |
| Ammo/shot      | 2                                 |
| Notes          | Best DPS at point-blank range     |

### Threat Scoring

The threat scoring model combines the enemy database with real-time spatial data:

```
base_threat = TIER_WEIGHTS[enemy.tier]          # T1=10, T2=25, T3=50, T4=100, T5=200
distance_mod = 1.0 / max(enemy.distance, 64)    # Closer = scarier
angle_mod = 1.5 if enemy.facing_player else 1.0 # Aiming at you = scarier
state_mod = 2.0 if enemy.attacking else 1.0     # Mid-attack = scarier
resurrect_mod = 3.0 if enemy.can_resurrect else 1.0  # Archviles jump the queue

threat = base_threat * distance_mod * angle_mod * state_mod * resurrect_mod
```

---

## Communication Protocol

### Bot to Player: VGS Callouts

The AI companion communicates to the human player through the VGS system (see
[VGS_COMMANDS.md](VGS_COMMANDS.md)). Callouts appear as HUD text and will eventually
support audio.

Key properties:
- Fixed vocabulary of 20 commands
- Priority-ranked (critical callouts override cooldowns)
- Rate-limited (3 sec global cooldown, 10 sec per-code cooldown)
- AI selects the single most relevant callout per evaluation cycle

### Claude to Bot: Behavior Commands

The strategic brain writes commands to a shared file that the ZScript bot reads:

| Command          | Effect                                              |
|------------------|-----------------------------------------------------|
| `follow`         | Return to Follow state, trail the player            |
| `attack_target`  | Switch to Attack state, prioritize specified target |
| `hold_position`  | Switch to Hold state at current location            |
| `retreat`        | Switch to Flee state, move toward player/health     |
| `flank_left`     | Move to the left of the player's facing direction   |
| `flank_right`    | Move to the right of the player's facing direction  |

Command file format:

```
COMMAND=attack_target
TARGET=PB_Archvile
TIMESTAMP=12450
```

The bot reads this file every few tics. If the timestamp hasn't changed, the previous
command persists. Commands don't expire -- the bot follows the last instruction until
a new one arrives or its FSM naturally transitions (e.g., all enemies dead -> Follow).

### Player to Bot: Input Bindings (Future)

Planned but not yet implemented. The human player will be able to issue VGS commands
to the bot via key bindings:

```
bind V "vgs_menu_open"    // Opens the VGS chord input mode
```

The bot would receive these as commands with the same priority system it uses for
its own decision-making.

---

## After Action Reports

### Purpose

After each session (or individual map), the system generates an After Action Report
(AAR) analyzing what happened and what could improve. These feed back into the
strategic brain's context for future sessions.

### Content

- **Death analysis** -- Where and how each death occurred. What enemy killed the
  player/bot? Could it have been avoided? Was there a missed `VEB` callout?
- **Damage profile** -- Damage dealt vs. taken, broken down by weapon and enemy type.
  Identifies inefficient weapon choices.
- **Weapon usage** -- Which weapons were used and how effectively. Ammo efficiency.
  Cases where a better weapon was available but not selected.
- **Movement analysis** -- Did the players stick together or split up? How often was
  the bot in Follow vs. Attack vs. Flee? Retreat frequency.
- **Callout effectiveness** -- Which VGS callouts were issued? Did they correlate
  with better outcomes? Were critical callouts (`VEB`) timely?
- **Tactical recommendations** -- Specific suggestions for the next session based on
  patterns. "Consider retreating earlier when facing multiple T4 enemies." "SSG is
  underused against close-range targets."

### Feedback Loop

AARs are stored as JSONL and optionally summarized by Claude. Key findings are
injected into the strategic brain's system prompt for subsequent sessions, allowing
the AI to learn from past mistakes without fine-tuning.

---

## Data Flow

```
+------------------+
|     GZDoom       |
|  (Game Engine)   |
|                  |
|  +------------+  |        +-----------------+
|  | ZScript    |  |  log   |                 |
|  | Telemetry  |--------->| telemetry.log   |
|  | Logger     |  |        |                 |
|  +------------+  |        +--------+--------+
|                  |                 |
|  +------------+  |                 | tail
|  | ZScript    |  |                 v
|  | Reflex Bot |  |        +--------+--------+
|  |            |  |        |  Python Bridge  |
|  | FSM:       |  |        |                 |
|  |  Follow    |  |        | - Parse events  |
|  |  Attack    |  |        | - Build state   |
|  |  Flee      |  |  read  | - Rate limit    |
|  |  Hold      |<-+-----  |                 |
|  |            |  |  cmd   +--------+--------+
|  +------------+  |  file           |
|                  |                 | API call (~1/sec)
+------------------+                 v
                            +--------+--------+
                            |   Claude API    |
                            |                 |
                            | - Evaluate state|
                            | - Pick VGS code |
                            | - Issue command |
                            | - Log reasoning |
                            +-----------------+


Post-Session:

telemetry.log --> Post-Processor --> per-map JSONL
                                 --> session summary
                                 --> After Action Report
                                           |
                                           v
                                    Future session
                                    system prompt
```

---

## Technology Stack

| Component            | Technology                        | Role                              |
|----------------------|-----------------------------------|-----------------------------------|
| Game engine          | GZDoom / UZDoom 4.2+              | Runs Doom, hosts ZScript mods     |
| Gameplay mod         | Project Brutality 3               | Expanded enemies, weapons, mechanics |
| Reflex bot           | ZScript (GZDoom native)           | 35 Hz combat AI, movement, aiming |
| Telemetry logger     | ZScript EventHandler              | Structured game state logging     |
| Bridge process       | Python 3.10+                      | Connects game to Claude API       |
| Strategic brain      | Claude API (Anthropic)            | Tactical decisions, VGS callouts  |
| Analysis tools       | Python (post-processing scripts)  | AARs, statistics, replay analysis |
| Command transport    | Shared file on disk               | ZScript <-> Python communication  |

### Why These Choices

- **ZScript** over ACS: ZScript has full object-oriented access to the game world.
  ACS is too limited for the actor inspection and FSM complexity we need.
- **File-based IPC** over sockets: GZDoom's ZScript has no networking API. Files are
  the only reliable bridge between the game process and external code. The latency
  (one disk read per few tics) is acceptable for strategic-level commands.
- **Claude** over local models: Strategic reasoning about complex Doom encounters
  benefits from Claude's ability to weigh multiple factors (enemy composition, ammo
  state, map geometry, player health) and produce nuanced decisions. Local models
  could handle simpler heuristics, but the goal is a companion that feels like playing
  with a skilled human.
- **Python** for the bridge: Fast enough for 1 Hz polling, excellent Claude SDK
  support, easy to prototype with.

---

## Future: Squad Mode

The long-term vision is inspired by Rainbow Six Vegas 2's squad command system:
a small team of AI bots with distinct roles, all commanded by Claude as squad leader.

### Concept

Instead of one AI companion, the player leads a 3-4 person squad:

```
Player (Squad Leader)
  |
  +-- Pointman Bot    (aggressive, leads entry, shotgun/SMG)
  +-- Support Bot     (mid-range, covers flanks, callouts, rifle)
  +-- Heavy Bot       (slow, high damage, holds chokepoints, rockets/BFG)
```

### Roles

| Role      | Behavior                                              | Preferred Weapons       |
|-----------|-------------------------------------------------------|-------------------------|
| Pointman  | First through doors, aggressive target engagement     | SSG, Minigun, Plasma    |
| Support   | Stays near player, covers flanks, prioritizes callouts| Rifle, Chaingun         |
| Heavy     | Hangs back, holds chokepoints, saves power weapons    | Rocket Launcher, BFG    |

### Breach-and-Clear

At marked doors or chokepoints, the player can order a breach:

1. Player marks the door (`VTK` or dedicated keybind)
2. Squad stacks up (bots move to entry positions)
3. Player triggers breach (`VTG` -- "Go go go!")
4. Pointman enters first, clears immediate threats
5. Support follows, covers opposite angle
6. Heavy holds the door, prevents enemies from flanking behind

### Claude as Commander

In squad mode, Claude's role expands from single-bot advisor to full squad commander.
Each API call returns commands for ALL bots:

```json
{
  "vgs": "VTG",
  "squad": [
    { "bot": "pointman", "command": "attack_target", "target": "PB_Cacodemon" },
    { "bot": "support", "command": "flank_right" },
    { "bot": "heavy", "command": "hold_position" }
  ]
}
```

This is a significant expansion of the current system but the architecture supports
it -- each bot is an independent ZScript actor reading from its own command file.
The Python bridge just needs to write multiple files instead of one.

### Prerequisites

- Stable single-bot co-op (current milestone)
- Multi-bot ZScript framework (spawn and manage N bots)
- Role-specific weapon selection and behavior tuning
- Expanded VGS vocabulary for squad commands
- Formation system (stack, line, spread)
