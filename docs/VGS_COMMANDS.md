# VGS Command Reference

## Overview

The Voice Game System (VGS) is a tactical callout system inspired by Hi-Rez Studios'
SMITE and Dynamix's Starsiege: Tribes. Players memorize short key-chord codes (like
`VEF` for "Enemy ahead!") to issue tactical callouts without breaking the flow of
combat. In Doom Copilot, both the human player and the AI companion share the same
command vocabulary.

Every VGS code starts with `V` (for "voice"), followed by a **category letter**, then
an **action letter**:

```
V + [Category] + [Action]
    A = Attack
    D = Defend
    E = Enemy
    S = Status
    T = Tactical
```

For example, `VEB` breaks down as:

```
V  = Voice
E  = Enemy category
B  = Behind you!
```

The system is intentionally small. Twenty commands cover the tactical space of a co-op
Doom session without overwhelming the player or flooding the HUD. Every callout maps
to a concrete combat situation.

---

## Command Reference

### Attack

Commands that push the pace. Use these to coordinate offensive movement.

| Code  | Callout          | When to Use                                        | Priority |
|-------|------------------|----------------------------------------------------|----------|
| `VAA` | "Attack!"        | General push forward, clear the room               | Normal   |
| `VAL` | "Attack left!"   | Flank left, split enemy attention                  | Normal   |
| `VAR` | "Attack right!"  | Flank right, split enemy attention                 | Normal   |
| `VAF` | "Focus fire!"    | Priority target needs concentrated damage (Archvile, boss, resurrector) | High |

### Defend

Commands that slow the pace or pull back. Use these when the situation is deteriorating.

| Code  | Callout          | When to Use                                        | Priority |
|-------|------------------|----------------------------------------------------|----------|
| `VDD` | "Hold here!"     | Good defensive position, stop advancing             | Normal   |
| `VDR` | "Retreat!"       | Fall back to previous area, fight is unwinnable     | High     |
| `VDC` | "Cover me!"      | Need suppressive fire while healing, switching, or repositioning | Normal |

### Enemy

Contact reports. These are the most time-sensitive callouts -- knowing where enemies
are keeps you alive.

| Code  | Callout            | When to Use                                      | Priority   |
|-------|--------------------|--------------------------------------------------|------------|
| `VEF` | "Enemy ahead!"     | Forward contact, enemies in the direction of movement | Normal  |
| `VEB` | "Behind you!"      | Rear threat the other player may not see         | **Critical** |
| `VEL` | "Left!"            | Enemy flanking from the left                     | High       |
| `VER` | "Right!"           | Enemy flanking from the right                    | High       |
| `VEH` | "Heavy incoming!"  | Tier 4+ enemy or boss entering the fight         | High       |

`VEB` is the single highest-priority callout in the system. A Revenant behind you that
you don't know about will kill you. The AI issues this immediately, bypassing normal
cooldown rules.

### Status

Self-reports. Let your co-op partner know your current state so they can adapt.

| Code  | Callout              | When to Use                                    | Priority |
|-------|----------------------|------------------------------------------------|----------|
| `VSR` | "Ready!"             | Full health, stocked on ammo, good to go       | Low      |
| `VSH` | "Need health!"       | HP below survivable threshold                  | Normal   |
| `VSA` | "Need ammo!"         | Primary weapon running dry                     | Normal   |
| `VSW` | "Swapping weapon!"   | Weapon change or brief repositioning pause      | Low      |

### Tactical

Movement and objective coordination.

| Code  | Callout             | When to Use                                     | Priority |
|-------|---------------------|-------------------------------------------------|----------|
| `VTF` | "Follow me!"        | Regroup on the caller's position                | Normal   |
| `VTS` | "Stay put!"         | Hold current position, don't follow             | Normal   |
| `VTG` | "Go go go!"         | Breach a door, push through a chokepoint        | High     |
| `VTK` | "Objective here!"   | Key, switch, or exit found                      | Normal   |

---

## How the AI Decides What to Call

The AI companion evaluates game state every tick and assigns each potential callout a
**relevance score** based on the current situation. The highest-scoring callout wins,
subject to cooldown rules. The scoring logic lives in `vgs_engine.py`.

Rough priority hierarchy:

1. **Critical threats** -- `VEB` (behind you) fires immediately if a monster is within
   damage range behind the human player.
2. **High-priority contacts** -- `VEH`, `VEL`, `VER` for flanking or heavy enemies.
3. **Tactical coordination** -- `VDR`, `VTG`, `VAF` based on the strategic brain's
   assessment of the fight.
4. **Status reports** -- `VSH`, `VSA` when the AI's own resources are low.
5. **Ambient callouts** -- `VSR`, `VEF` fill silence during calm moments.

The AI never spams. It issues the single most important callout available, respects
cooldowns, and stays quiet when there's nothing useful to say.

---

## Cooldown Rules

VGS callouts are rate-limited to avoid noise:

| Rule                  | Cooldown | Notes                                         |
|-----------------------|----------|-----------------------------------------------|
| **Global cooldown**   | 3 sec    | Minimum time between any two callouts         |
| **Per-code cooldown** | 10 sec   | Same code cannot repeat within this window    |
| **Critical override** | 0 sec    | `VEB` bypasses global cooldown entirely       |

These values are tuned for the pace of Project Brutality 3, which is faster and more
chaotic than vanilla Doom. In calmer mapsets, the per-code cooldown could be extended.

---

## Future: Voice Audio

The VGS system is designed to support audio callouts. Each command code maps to a
single audio file:

```
audio/
  vgs/
    vaa_attack.ogg
    val_attack_left.ogg
    var_attack_right.ogg
    vaf_focus_fire.ogg
    ...
```

Audio playback would be triggered by the Python bridge when a callout is issued,
playing through a dedicated audio channel so it doesn't compete with game sound. The
bot's "voice" would be distinct -- short, punchy clips designed to cut through PB3's
dense sound mix.

Until audio is implemented, callouts display as HUD text using GZDoom's `A_Log` or
a custom HUD widget.

---

## Quick Reference Card

```
ATTACK          DEFEND          ENEMY           STATUS          TACTICAL
VAA Attack!     VDD Hold here!  VEF Ahead!      VSR Ready!      VTF Follow me!
VAL Left!       VDR Retreat!    VEB Behind you!  VSH Need HP!    VTS Stay put!
VAR Right!      VDC Cover me!   VEL Left!        VSA Need ammo!  VTG Go go go!
VAF Focus fire!                 VER Right!       VSW Swapping!   VTK Objective!
                                VEH Heavy!
```
