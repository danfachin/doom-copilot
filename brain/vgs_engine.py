"""
VGS Decision Engine — Doom Copilot tactical callout system.

Takes a game state snapshot and returns the highest-priority VGS callout
(or None if silence is the right call). Inspired by SMITE's Voice Game System:
a fixed vocabulary of tactical callouts that map cleanly to audio cues.

Priority tiers:
  1. CRITICAL  — Archvile detected, rear threat, near-death retreat
  2. TACTICAL  — Heavy incoming, flank warnings, low HP/ammo
  3. STRATEGIC — Push, hold, breach (only when nothing more urgent)

Cooldown system prevents callout spam:
  - 3 second minimum between ANY callout
  - 10 second minimum before repeating the SAME code

No external dependencies — stdlib only.
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Optional


# ── VGS Command Definitions ────────────────────────────────────────────────

class Priority(IntEnum):
    """Callout priority tiers. Higher value = more urgent."""
    STRATEGIC = 1
    TACTICAL = 2
    CRITICAL = 3


@dataclass(frozen=True)
class VGSCommand:
    code: str
    text: str
    priority: Priority


# Full command table
VGS = {
    # Attack
    "VAA": VGSCommand("VAA", "Attack!", Priority.STRATEGIC),
    "VAL": VGSCommand("VAL", "Attack left!", Priority.TACTICAL),
    "VAR": VGSCommand("VAR", "Attack right!", Priority.TACTICAL),
    "VAF": VGSCommand("VAF", "Focus fire!", Priority.CRITICAL),
    # Defend
    "VDD": VGSCommand("VDD", "Hold here!", Priority.STRATEGIC),
    "VDR": VGSCommand("VDR", "Retreat!", Priority.CRITICAL),
    "VDC": VGSCommand("VDC", "Cover me!", Priority.TACTICAL),
    # Enemy
    "VEF": VGSCommand("VEF", "Enemy ahead!", Priority.TACTICAL),
    "VEB": VGSCommand("VEB", "Behind you!", Priority.CRITICAL),
    "VEL": VGSCommand("VEL", "Left!", Priority.TACTICAL),
    "VER": VGSCommand("VER", "Right!", Priority.TACTICAL),
    "VEH": VGSCommand("VEH", "Heavy incoming!", Priority.TACTICAL),
    # Status
    "VSR": VGSCommand("VSR", "Ready!", Priority.STRATEGIC),
    "VSH": VGSCommand("VSH", "Need health!", Priority.TACTICAL),
    "VSA": VGSCommand("VSA", "Need ammo!", Priority.TACTICAL),
    # Tactics
    "VTF": VGSCommand("VTF", "Follow me!", Priority.STRATEGIC),
    "VTS": VGSCommand("VTS", "Stay put!", Priority.STRATEGIC),
    "VTG": VGSCommand("VTG", "Go go go!", Priority.STRATEGIC),
    "VTK": VGSCommand("VTK", "Objective here!", Priority.TACTICAL),
}


# ── Enemy Tier Classification ──────────────────────────────────────────────

class EnemyTier(IntEnum):
    """PB3 enemy tiers by max HP."""
    T1 = 1   # Grunts: 70-100 HP (zombies, imps, sergeants)
    T2 = 2   # Midweight: ~200 HP (pinkies, spectres)
    T3 = 3   # Heavy: 300-900 HP (cacodemons, revenants, mancubi, arachnotrons)
    T4 = 4   # Elite: 650-1300 HP (barons, hell knights, archviles)
    BOSS = 5  # Bosses: 5000-8500 HP (cyberdemon, spider mastermind)


# Archvile class names in PB3 (they resurrect the dead — top priority ALWAYS)
ARCHVILE_CLASSES = frozenset({
    "Archvile", "PB_Archvile", "PB_ArchvileBase", "PB_Archvile1",
    "PB_Archvile2", "PB_DarkArchvile", "PB_ArchvilePE",
})


def classify_tier(maxhp: int, class_name: str = "") -> EnemyTier:
    """Classify an enemy into a PB3 tier based on max HP."""
    if maxhp >= 5000:
        return EnemyTier.BOSS
    if maxhp >= 650 or class_name in ARCHVILE_CLASSES:
        return EnemyTier.T4
    if maxhp >= 300:
        return EnemyTier.T3
    if maxhp >= 200:
        return EnemyTier.T2
    return EnemyTier.T1


# ── Data Model ─────────────────────────────────────────────────────────────

@dataclass
class EnemySnapshot:
    """A single enemy observed in the current scan."""
    class_name: str
    distance: float      # map units from player
    angle: float         # relative angle in degrees (-180 to 180), 0 = directly ahead
    hp: int
    maxhp: int
    state: str           # idle, chase, missile, melee


@dataclass
class PlayerState:
    """Player status from the most recent state event."""
    px: float = 0.0
    py: float = 0.0
    pz: float = 0.0
    angle: float = 0.0   # absolute facing angle
    hp: int = 100
    armor: int = 0
    weapon: str = "None"
    ammo: int = 0
    kills: int = 0
    vx: float = 0.0
    vy: float = 0.0

    @property
    def speed(self) -> float:
        return math.sqrt(self.vx ** 2 + self.vy ** 2)

    @property
    def is_moving(self) -> bool:
        return self.speed > 2.0


@dataclass
class GameState:
    """Complete snapshot of the game at decision time."""
    player: PlayerState
    enemies: list[EnemySnapshot] = field(default_factory=list)
    tic: int = 0
    map_name: str = ""
    # Recent history (filled by the bridge layer)
    recent_damage_taken: int = 0        # damage in last ~3 seconds
    recent_deaths: int = 0              # deaths in last ~10 seconds
    time_stationary: float = 0.0        # seconds player hasn't moved
    recent_resurrections: int = 0       # archvile revives in last ~5 seconds


@dataclass
class VGSCallout:
    """A callout decision from the engine."""
    code: str
    text: str
    priority: Priority
    reason: str          # human-readable explanation of why this was chosen
    threat_score: float = 0.0  # score of the triggering threat, if any

    def __str__(self) -> str:
        return f"[{self.code}] \"{self.text}\" (P{self.priority.value}: {self.reason})"


# ── Threat Scoring ─────────────────────────────────────────────────────────

def threat_score(enemy: EnemySnapshot) -> float:
    """
    Score an enemy's threat level. Higher = more dangerous right now.

    Factors:
      - Tier/HP: bigger enemies are scarier (up to 50 pts)
      - Distance: closer = more dangerous (up to 30 pts)
      - Behavior: actively attacking > chasing > idle (up to 15 pts)
      - Angle: behind the player = can't see it = dangerous (up to 15 pts)
      - Special: Archviles get maximum score — they undo your kills
    """
    # Archviles always score maximum — they're the most dangerous enemy
    # in Doom because they resurrect dead enemies behind you
    if enemy.class_name in ARCHVILE_CLASSES:
        return 100.0

    score = 0.0

    # Tier/HP component (0-50)
    tier = classify_tier(enemy.maxhp, enemy.class_name)
    tier_scores = {
        EnemyTier.T1: 5,
        EnemyTier.T2: 15,
        EnemyTier.T3: 25,
        EnemyTier.T4: 40,
        EnemyTier.BOSS: 50,
    }
    score += tier_scores.get(tier, 5)

    # Distance component (0-30): closer = more threatening
    # 0 units -> 30 pts, 2048 units -> 0 pts, linear falloff
    dist_factor = max(0.0, 1.0 - (enemy.distance / 2048.0))
    score += dist_factor * 30.0

    # Behavior state component (0-15)
    state_scores = {
        "idle": 0,
        "chase": 5,
        "missile": 15,   # actively shooting at you
        "melee": 12,     # in your face
    }
    score += state_scores.get(enemy.state, 0)

    # Angle component (0-15): enemies behind player are more dangerous
    abs_angle = abs(enemy.angle)
    if abs_angle > 120:
        score += 15  # behind you — can't see it
    elif abs_angle > 90:
        score += 8   # peripheral vision
    elif abs_angle > 60:
        score += 3   # off to the side

    return score


# ── Cooldown Manager ───────────────────────────────────────────────────────

class CooldownManager:
    """
    Prevents callout spam.
    - 3 seconds minimum between any callout
    - 10 seconds before repeating the same code
    """

    GLOBAL_COOLDOWN = 3.0       # seconds between any callout
    REPEAT_COOLDOWN = 10.0      # seconds before same code can repeat

    def __init__(self):
        self._last_any: float = -999.0
        self._last_by_code: dict[str, float] = {}

    def can_fire(self, code: str, now: float | None = None) -> bool:
        """Check if a callout is allowed right now."""
        if now is None:
            now = time.monotonic()

        # Global cooldown
        if now - self._last_any < self.GLOBAL_COOLDOWN:
            return False

        # Per-code cooldown
        last = self._last_by_code.get(code, -999.0)
        if now - last < self.REPEAT_COOLDOWN:
            return False

        return True

    def record(self, code: str, now: float | None = None) -> None:
        """Record that a callout was issued."""
        if now is None:
            now = time.monotonic()
        self._last_any = now
        self._last_by_code[code] = now

    def reset(self) -> None:
        """Clear all cooldowns (e.g. on map change)."""
        self._last_any = -999.0
        self._last_by_code.clear()


# ── Decision Engine ────────────────────────────────────────────────────────

class VGSEngine:
    """
    The tactical brain. Feed it a GameState, get back the highest-priority
    callout (or None if staying quiet is the right move).
    """

    def __init__(self):
        self.cooldowns = CooldownManager()

    def decide(self, state: GameState, now: float | None = None) -> Optional[VGSCallout]:
        """
        Evaluate the game state and return the best callout.

        Checks are ordered by priority tier. Within a tier, the first
        matching rule wins. The cooldown system may suppress a callout
        even if a rule matches — in that case we try the next rule.
        """
        if now is None:
            now = time.monotonic()

        # Build scored enemy list (reused across multiple checks)
        scored = [(e, threat_score(e)) for e in state.enemies]
        scored.sort(key=lambda x: x[1], reverse=True)

        # Collect all candidate callouts, ordered by priority
        candidates: list[VGSCallout] = []

        # ── CRITICAL TIER ──────────────────────────────────────────

        # 1. Archvile detected — always focus fire
        for enemy, score in scored:
            if enemy.class_name in ARCHVILE_CLASSES:
                candidates.append(VGSCallout(
                    code="VAF",
                    text=VGS["VAF"].text,
                    priority=Priority.CRITICAL,
                    reason=f"Archvile detected at {enemy.distance:.0f} units ({enemy.state})",
                    threat_score=score,
                ))
                break  # one archvile callout is enough

        # 2. Significant enemy behind player (angle > 120, tier >= T2)
        for enemy, score in scored:
            if abs(enemy.angle) > 120 and classify_tier(enemy.maxhp, enemy.class_name) >= EnemyTier.T2:
                candidates.append(VGSCallout(
                    code="VEB",
                    text=VGS["VEB"].text,
                    priority=Priority.CRITICAL,
                    reason=f"{enemy.class_name} behind you at {enemy.distance:.0f}u (angle {enemy.angle:.0f})",
                    threat_score=score,
                ))
                break

        # 3. Near-death retreat: HP < 25 with enemies close
        close_enemies = [e for e, _ in scored if e.distance < 512]
        if state.player.hp < 25 and close_enemies:
            candidates.append(VGSCallout(
                code="VDR",
                text=VGS["VDR"].text,
                priority=Priority.CRITICAL,
                reason=f"HP {state.player.hp}, {len(close_enemies)} enemies within 512u — get out",
                threat_score=90.0,
            ))

        # ── TACTICAL TIER ──────────────────────────────────────────

        # 4. Heavy/Boss enemy within engagement range
        for enemy, score in scored:
            tier = classify_tier(enemy.maxhp, enemy.class_name)
            if tier >= EnemyTier.T4 and enemy.distance < 1500:
                candidates.append(VGSCallout(
                    code="VEH",
                    text=VGS["VEH"].text,
                    priority=Priority.TACTICAL,
                    reason=f"{enemy.class_name} (T{tier.value}) at {enemy.distance:.0f}u",
                    threat_score=score,
                ))
                break

        # 5. Flank warning: 5+ enemies concentrated on one side
        left_enemies = [e for e in state.enemies if -160 < e.angle < -30]
        right_enemies = [e for e in state.enemies if 30 < e.angle < 160]

        if len(left_enemies) > 5:
            candidates.append(VGSCallout(
                code="VEL",
                text=VGS["VEL"].text,
                priority=Priority.TACTICAL,
                reason=f"{len(left_enemies)} enemies on left flank",
            ))
        if len(right_enemies) > 5:
            candidates.append(VGSCallout(
                code="VER",
                text=VGS["VER"].text,
                priority=Priority.TACTICAL,
                reason=f"{len(right_enemies)} enemies on right flank",
            ))

        # 6. Low HP warning
        if state.player.hp < 50:
            candidates.append(VGSCallout(
                code="VSH",
                text=VGS["VSH"].text,
                priority=Priority.TACTICAL,
                reason=f"HP at {state.player.hp}",
            ))

        # 7. Low ammo warning
        if state.player.ammo <= 5 and state.player.weapon != "Fist" and state.player.weapon != "None":
            candidates.append(VGSCallout(
                code="VSA",
                text=VGS["VSA"].text,
                priority=Priority.TACTICAL,
                reason=f"Only {state.player.ammo} ammo for {state.player.weapon}",
            ))

        # ── STRATEGIC TIER ─────────────────────────────────────────

        # 8. Fortified position: many enemies ahead, player has cover (stationary)
        ahead_enemies = [e for e in state.enemies if abs(e.angle) < 45]
        if len(ahead_enemies) > 8 and not state.player.is_moving:
            candidates.append(VGSCallout(
                code="VDD",
                text=VGS["VDD"].text,
                priority=Priority.STRATEGIC,
                reason=f"{len(ahead_enemies)} enemies ahead, holding position",
            ))

        # 9. Stagnation: player hasn't moved in a while, push them
        elif state.time_stationary > 8.0 and len(state.enemies) < 3:
            candidates.append(VGSCallout(
                code="VTG",
                text=VGS["VTG"].text,
                priority=Priority.STRATEGIC,
                reason=f"Stationary for {state.time_stationary:.0f}s, area looks clear",
            ))

        # 10. Path clear: few/no enemies visible
        elif len(state.enemies) <= 2 and state.player.hp >= 50:
            candidates.append(VGSCallout(
                code="VAA",
                text=VGS["VAA"].text,
                priority=Priority.STRATEGIC,
                reason="Area mostly clear, push forward",
            ))

        # ── Pick the best candidate that passes cooldown ───────────

        # Sort by priority (descending), then threat score (descending)
        candidates.sort(key=lambda c: (c.priority.value, c.threat_score), reverse=True)

        for callout in candidates:
            if self.cooldowns.can_fire(callout.code, now):
                self.cooldowns.record(callout.code, now)
                return callout

        return None


# ── Synthetic Test Scenarios ───────────────────────────────────────────────

def _run_scenarios() -> None:
    """Quick smoke test with synthetic game states."""
    engine = VGSEngine()

    separator = "-" * 60

    print("=" * 60)
    print("  VGS Engine — Synthetic Scenario Tests")
    print("=" * 60)

    # Scenario 1: Archvile detected
    print(f"\n{separator}")
    print("Scenario 1: Archvile detected at medium range")
    state = GameState(
        player=PlayerState(hp=80, armor=50, weapon="SuperShotgun", ammo=20),
        enemies=[
            EnemySnapshot("PB_Imp1", 400, 10.0, 70, 70, "chase"),
            EnemySnapshot("PB_Archvile", 800, -20.0, 700, 700, "missile"),
            EnemySnapshot("PB_Sergeant", 300, 45.0, 30, 30, "chase"),
        ],
    )
    result = engine.decide(state, now=0.0)
    print(f"  Result: {result}")
    assert result is not None and result.code == "VAF", f"Expected VAF, got {result}"

    # Scenario 2: Enemy behind player
    print(f"\n{separator}")
    print("Scenario 2: Revenant sneaking up behind")
    state = GameState(
        player=PlayerState(hp=70, armor=30, weapon="PB_Rifle", ammo=60),
        enemies=[
            EnemySnapshot("PB_Imp1", 500, 15.0, 60, 70, "chase"),
            EnemySnapshot("PB_Revenant", 300, 150.0, 300, 300, "chase"),
        ],
    )
    result = engine.decide(state, now=20.0)
    print(f"  Result: {result}")
    assert result is not None and result.code == "VEB", f"Expected VEB, got {result}"

    # Scenario 3: Critical HP, enemies close
    print(f"\n{separator}")
    print("Scenario 3: Near-death, enemies closing in")
    state = GameState(
        player=PlayerState(hp=18, armor=0, weapon="SuperShotgun", ammo=4),
        enemies=[
            EnemySnapshot("PB_Pinky", 200, 30.0, 180, 200, "melee"),
            EnemySnapshot("PB_Imp1", 150, -40.0, 50, 70, "chase"),
            EnemySnapshot("PB_Sergeant", 400, 10.0, 25, 30, "chase"),
        ],
    )
    result = engine.decide(state, now=40.0)
    print(f"  Result: {result}")
    assert result is not None and result.code == "VDR", f"Expected VDR, got {result}"

    # Scenario 4: Cyberdemon appears
    print(f"\n{separator}")
    print("Scenario 4: Cyberdemon at range")
    state = GameState(
        player=PlayerState(hp=100, armor=100, weapon="PB_PlasmaRifle", ammo=300),
        enemies=[
            EnemySnapshot("PB_Cyberdemon", 1200, 5.0, 8500, 8500, "chase"),
            EnemySnapshot("PB_Imp1", 600, -60.0, 70, 70, "idle"),
        ],
    )
    result = engine.decide(state, now=60.0)
    print(f"  Result: {result}")
    assert result is not None and result.code == "VEH", f"Expected VEH, got {result}"

    # Scenario 5: All clear, push forward
    print(f"\n{separator}")
    print("Scenario 5: Area clear, full health")
    state = GameState(
        player=PlayerState(hp=100, armor=80, weapon="SuperShotgun", ammo=30),
        enemies=[
            EnemySnapshot("PB_Imp1", 1800, 10.0, 60, 70, "idle"),
        ],
    )
    result = engine.decide(state, now=80.0)
    print(f"  Result: {result}")
    assert result is not None and result.code == "VAA", f"Expected VAA, got {result}"

    # Scenario 6: Low HP warning
    print(f"\n{separator}")
    print("Scenario 6: Low HP, no immediate danger")
    state = GameState(
        player=PlayerState(hp=35, armor=0, weapon="PB_Rifle", ammo=40),
        enemies=[
            EnemySnapshot("PB_Imp1", 1200, 20.0, 50, 70, "idle"),
        ],
    )
    result = engine.decide(state, now=100.0)
    print(f"  Result: {result}")
    assert result is not None and result.code == "VSH", f"Expected VSH, got {result}"

    # Scenario 7: Cooldown suppression
    print(f"\n{separator}")
    print("Scenario 7: Same scenario 1 second later — should be suppressed by cooldown")
    result = engine.decide(state, now=101.0)  # only 1s after last callout
    print(f"  Result: {result}")
    assert result is None, f"Expected None (cooldown), got {result}"

    # Scenario 8: Massive left flank
    print(f"\n{separator}")
    print("Scenario 8: 6 enemies on left flank")
    state = GameState(
        player=PlayerState(hp=80, armor=40, weapon="PB_Chaingun", ammo=200),
        enemies=[
            EnemySnapshot("PB_Imp1", 400, -60.0, 60, 70, "chase"),
            EnemySnapshot("PB_Imp1", 350, -80.0, 70, 70, "chase"),
            EnemySnapshot("PB_Sergeant", 500, -45.0, 28, 30, "chase"),
            EnemySnapshot("PB_Zombie", 450, -90.0, 15, 20, "chase"),
            EnemySnapshot("PB_Imp1", 380, -70.0, 65, 70, "missile"),
            EnemySnapshot("PB_Sergeant", 520, -55.0, 30, 30, "chase"),
        ],
    )
    result = engine.decide(state, now=120.0)
    print(f"  Result: {result}")
    assert result is not None and result.code == "VEL", f"Expected VEL, got {result}"

    # Scenario 9: Player camping, area clear — push them
    print(f"\n{separator}")
    print("Scenario 9: Player stationary for 10 seconds, no enemies")
    state = GameState(
        player=PlayerState(hp=100, armor=100, weapon="SuperShotgun", ammo=50),
        enemies=[],
        time_stationary=10.0,
    )
    result = engine.decide(state, now=140.0)
    print(f"  Result: {result}")
    assert result is not None and result.code == "VTG", f"Expected VTG, got {result}"

    # Scenario 10: Threat scoring
    print(f"\n{separator}")
    print("Scenario 10: Threat score comparison")
    idle_imp = EnemySnapshot("PB_Imp1", 800, 10.0, 60, 70, "idle")
    close_rev = EnemySnapshot("PB_Revenant", 200, 30.0, 300, 300, "missile")
    far_cyber = EnemySnapshot("PB_Cyberdemon", 1500, 0.0, 8500, 8500, "chase")
    archvile = EnemySnapshot("PB_Archvile", 1000, -150.0, 700, 700, "idle")

    scores = {
        "Idle imp (800u)": threat_score(idle_imp),
        "Close revenant (200u, missile)": threat_score(close_rev),
        "Far cyberdemon (1500u, chase)": threat_score(far_cyber),
        "Archvile (always max)": threat_score(archvile),
    }
    for label, s in scores.items():
        print(f"  {label}: {s:.1f}")

    assert scores["Archvile (always max)"] == 100.0
    assert scores["Close revenant (200u, missile)"] > scores["Idle imp (800u)"]
    assert scores["Archvile (always max)"] > scores["Far cyberdemon (1500u, chase)"]

    print(f"\n{'=' * 60}")
    print("  All scenarios passed.")
    print("=" * 60)


if __name__ == "__main__":
    _run_scenarios()
