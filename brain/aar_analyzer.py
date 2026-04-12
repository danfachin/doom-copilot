"""
After Action Report (AAR) Analyzer — Doom Copilot.

Reads processed session data (JSONL event streams + summary.json from
process_logs.py) and generates detailed tactical analysis reports.

Reports cover:
  - Per-map breakdowns (kills, deaths, damage, weapons, patterns)
  - Death analysis with preceding event narrative
  - Damage source ranking
  - Weapon usage with visual bars
  - Movement/engagement style analysis
  - Cross-session tactical recommendations for the AI companion

Usage:
    python brain/aar_analyzer.py data/processed/session_20260412_203000/

No external dependencies — stdlib only.
"""

from __future__ import annotations

import json
import math
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

TICS_PER_SEC = 35.0
BAR_WIDTH = 20  # character width for visual bars


# ── Data Structures ────────────────────────────────────────────────────────

@dataclass
class DeathEvent:
    """Reconstructed narrative around a player death."""
    tic: int
    time_human: str
    killed_by: str
    map_name: str
    kills_at_death: int
    hp_before: int           # HP from last state before death
    position: tuple[float, float]  # px, py at death
    velocity: tuple[float, float]  # vx, vy at death
    preceding_damage: list[dict]   # hurt events in the ~3 seconds before death
    insight: str             # generated tactical insight


@dataclass
class MapAnalysis:
    """Full analysis of a single map run."""
    map_name: str
    skill: int
    duration_sec: float
    duration_human: str
    kills: int
    deaths: int
    damage_taken: int
    weapon_usage: dict[str, int]     # weapon -> state sample count
    damage_sources: dict[str, int]   # enemy class -> total damage
    damage_source_counts: dict[str, int]  # enemy class -> hit count
    death_events: list[DeathEvent]
    avg_engagement_distance: float
    time_below_50hp_pct: float
    avg_speed: float
    hp_samples: list[int]
    positions: list[tuple[float, float]]
    enemy_encounters: dict[str, int]  # class -> times seen
    resurrections: int


@dataclass
class SessionAnalysis:
    """Aggregate analysis across all maps in a session."""
    session_dir: Path
    timestamp: str
    maps: list[MapAnalysis]
    total_kills: int
    total_deaths: int
    total_damage: int
    total_duration_sec: float
    all_weapon_usage: dict[str, int]
    all_damage_sources: dict[str, int]
    recommendations: list[str]


# ── Event Stream Parsing ───────────────────────────────────────────────────

def load_events(jsonl_path: Path) -> list[dict]:
    """Load events from a JSONL file."""
    events = []
    with open(jsonl_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return events


def tic_to_time(tic: int) -> str:
    """Convert tic count to m:ss string."""
    sec = tic / TICS_PER_SEC
    return f"{int(sec // 60)}:{int(sec % 60):02d}"


def tic_to_seconds(tic: int) -> float:
    """Convert tic count to seconds."""
    return tic / TICS_PER_SEC


# ── Death Analysis ─────────────────────────────────────────────────────────

def analyze_deaths(events: list[dict]) -> list[DeathEvent]:
    """
    For each player_death event, reconstruct what happened:
    - Find the last known player state before death
    - Gather all damage events in the preceding ~3 seconds (105 tics)
    - Generate a tactical insight
    """
    deaths = []
    state_events = [e for e in events if e.get("t") == "state"]
    hurt_events = [e for e in events if e.get("t") == "hurt"]
    death_events = [e for e in events if e.get("t") == "player_death"]

    for death in death_events:
        death_tic = death.get("tic", 0)

        # Last known state before death
        prior_states = [s for s in state_events if s.get("tic", 0) < death_tic]
        if prior_states:
            last_state = prior_states[-1]
            hp_before = last_state.get("hp", 0)
            position = (last_state.get("px", 0), last_state.get("py", 0))
            velocity = (last_state.get("vx", 0), last_state.get("vy", 0))
        else:
            hp_before = 0
            position = (0.0, 0.0)
            velocity = (0.0, 0.0)

        # Preceding damage (within ~3 seconds before death)
        lookback_tics = int(3.0 * TICS_PER_SEC)
        preceding = [
            h for h in hurt_events
            if death_tic - lookback_tics <= h.get("tic", 0) <= death_tic
        ]

        # Generate insight
        total_preceding_dmg = sum(h.get("dmg", 0) for h in preceding)
        insight = _generate_death_insight(
            death, preceding, hp_before, velocity, prior_states
        )

        deaths.append(DeathEvent(
            tic=death_tic,
            time_human=tic_to_time(death_tic),
            killed_by=death.get("killed_by", "unknown"),
            map_name=death.get("map", "unknown"),
            kills_at_death=death.get("kills", 0),
            hp_before=hp_before,
            position=position,
            velocity=velocity,
            preceding_damage=preceding,
            insight=insight,
        ))

    return deaths


def _generate_death_insight(
    death: dict,
    preceding_damage: list[dict],
    hp_before: int,
    velocity: tuple[float, float],
    prior_states: list[dict],
) -> str:
    """Generate a human-readable tactical insight about why the player died."""
    insights = []

    # Check if player was low HP for a while before dying
    if hp_before < 40:
        insights.append(f"was already low ({hp_before} HP) before the fatal hit")

    # Check if player took rapid successive hits
    if len(preceding_damage) >= 4:
        sources = set(h.get("src", "?") for h in preceding_damage)
        if len(sources) > 2:
            insights.append(f"caught in crossfire from {len(sources)} sources")
        else:
            insights.append(f"took {len(preceding_damage)} hits in rapid succession")

    # Check if player was standing still
    speed = math.sqrt(velocity[0] ** 2 + velocity[1] ** 2)
    if speed < 2.0:
        insights.append("was standing still when killed")
    elif speed > 15.0:
        insights.append("was moving fast but couldn't escape")

    # Check for sustained damage without retreat
    if len(prior_states) >= 6:
        recent_hp = [s.get("hp", 100) for s in prior_states[-6:]]
        if all(h < 50 for h in recent_hp):
            insights.append("spent too long below 50 HP without finding health")

    if not insights:
        insights.append("sudden death — limited warning")

    return "; ".join(insights)


# ── Damage Pattern Analysis ────────────────────────────────────────────────

def analyze_damage_patterns(events: list[dict]) -> tuple[dict[str, int], dict[str, int], float]:
    """
    Analyze which enemies deal the most damage and from what directions.

    Returns:
        (damage_by_source, hit_count_by_source, pct_damage_from_behind)
    """
    damage_by_source: Counter[str] = Counter()
    hits_by_source: Counter[str] = Counter()
    behind_damage = 0
    total_damage = 0

    hurt_events = [e for e in events if e.get("t") == "hurt"]
    state_events = [e for e in events if e.get("t") == "state"]
    enemy_events = [e for e in events if e.get("t") == "enemy"]

    for hurt in hurt_events:
        dmg = hurt.get("dmg", 0)
        src = hurt.get("src", "world")
        tic = hurt.get("tic", 0)

        damage_by_source[src] += dmg
        hits_by_source[src] += 1
        total_damage += dmg

        # Check if the damage source was behind the player
        # Find enemy scan closest to this tic
        nearby_enemies = [
            e for e in enemy_events
            if abs(e.get("tic", 0) - tic) < 36 and e.get("class", "") == src
        ]
        for enemy in nearby_enemies:
            if abs(enemy.get("angle", 0)) > 90:
                behind_damage += dmg
                break

    pct_behind = (behind_damage / total_damage * 100) if total_damage > 0 else 0
    return dict(damage_by_source.most_common()), dict(hits_by_source.most_common()), pct_behind


# ── Weapon Usage Analysis ──────────────────────────────────────────────────

def analyze_weapon_usage(events: list[dict]) -> dict[str, int]:
    """
    Track weapon usage by counting state snapshots per weapon.
    Each snapshot represents ~0.5 seconds of play.
    """
    weapon_counts: Counter[str] = Counter()
    for ev in events:
        if ev.get("t") == "state":
            w = ev.get("weapon", "None")
            if w != "None":
                weapon_counts[w] += 1
    return dict(weapon_counts.most_common())


# ── Movement Analysis ──────────────────────────────────────────────────────

@dataclass
class MovementStats:
    avg_speed: float
    max_speed: float
    time_stationary_pct: float
    total_distance: float
    avg_engagement_distance: float
    style: str  # "aggressive", "cautious", "mixed"


def analyze_movement(events: list[dict]) -> MovementStats:
    """
    Analyze player movement patterns:
    - Average/max speed
    - Time spent stationary
    - Engagement distances (how close enemies are during combat)
    - Overall playstyle classification
    """
    speeds: list[float] = []
    positions: list[tuple[float, float]] = []
    engagement_distances: list[float] = []

    state_events = [e for e in events if e.get("t") == "state"]
    enemy_events = [e for e in events if e.get("t") == "enemy"]

    for ev in state_events:
        vx = ev.get("vx", 0)
        vy = ev.get("vy", 0)
        speed = math.sqrt(vx ** 2 + vy ** 2)
        speeds.append(speed)
        positions.append((ev.get("px", 0), ev.get("py", 0)))

    # Engagement distances: average distance to enemies during combat tics
    combat_tics: set[int] = set()
    for ev in events:
        if ev.get("t") in ("hurt", "kill"):
            combat_tics.add(ev.get("tic", 0))

    for ev in enemy_events:
        tic = ev.get("tic", 0)
        # Consider enemies within +/-1 second of combat events as engagement distances
        if any(abs(tic - ct) < 35 for ct in combat_tics):
            engagement_distances.append(ev.get("dist", 0))

    # Total distance traveled
    total_dist = 0.0
    for i in range(1, len(positions)):
        dx = positions[i][0] - positions[i - 1][0]
        dy = positions[i][1] - positions[i - 1][1]
        total_dist += math.sqrt(dx ** 2 + dy ** 2)

    avg_speed = sum(speeds) / len(speeds) if speeds else 0
    max_speed = max(speeds) if speeds else 0
    stationary = sum(1 for s in speeds if s < 2.0)
    stationary_pct = (stationary / len(speeds) * 100) if speeds else 0
    avg_engage = (
        sum(engagement_distances) / len(engagement_distances)
        if engagement_distances else 0
    )

    # Classify style
    if avg_engage < 350 and stationary_pct < 20:
        style = "aggressive (close range, high mobility)"
    elif avg_engage > 700 or stationary_pct > 40:
        style = "cautious (ranged, positional)"
    else:
        style = "mixed (adaptive engagement ranges)"

    return MovementStats(
        avg_speed=avg_speed,
        max_speed=max_speed,
        time_stationary_pct=stationary_pct,
        total_distance=total_dist,
        avg_engagement_distance=avg_engage,
        style=style,
    )


# ── Per-Map Analysis ───────────────────────────────────────────────────────

def analyze_map_events(events: list[dict]) -> MapAnalysis:
    """Run all analysis passes on a single map's event stream."""
    # Basic info from map_start/map_end
    map_name = "unknown"
    skill = -1
    max_tic = 0
    kills = 0
    deaths_count = 0
    resurrections = 0
    hp_samples: list[int] = []
    positions: list[tuple[float, float]] = []

    for ev in events:
        t = ev.get("t")
        tic = ev.get("tic", 0)
        max_tic = max(max_tic, tic)

        if t == "map_start":
            map_name = ev.get("map", map_name)
            skill = ev.get("skill", skill)
        elif t == "map_end":
            map_name = ev.get("map", map_name)
            kills = ev.get("kills", kills)
        elif t == "state":
            hp_samples.append(ev.get("hp", 100))
            positions.append((ev.get("px", 0), ev.get("py", 0)))
        elif t == "player_death":
            deaths_count += 1
        elif t == "revived":
            resurrections += 1

    duration_sec = max_tic / TICS_PER_SEC if max_tic > 0 else 0
    duration_human = f"{int(duration_sec // 60)}:{int(duration_sec % 60):02d}"

    # Sub-analyses
    death_events = analyze_deaths(events)
    damage_sources, damage_counts, _ = analyze_damage_patterns(events)
    weapon_usage = analyze_weapon_usage(events)
    movement = analyze_movement(events)

    total_damage = sum(damage_sources.values())
    below_50 = sum(1 for h in hp_samples if h < 50)
    below_50_pct = (below_50 / len(hp_samples) * 100) if hp_samples else 0

    # Enemy encounters
    enemy_encounters: Counter[str] = Counter()
    for ev in events:
        if ev.get("t") == "enemy":
            enemy_encounters[ev.get("class", "?")] += 1

    return MapAnalysis(
        map_name=map_name,
        skill=skill,
        duration_sec=duration_sec,
        duration_human=duration_human,
        kills=kills,
        deaths=deaths_count,
        damage_taken=total_damage,
        weapon_usage=weapon_usage,
        damage_sources=damage_sources,
        damage_source_counts=damage_counts,
        death_events=death_events,
        avg_engagement_distance=movement.avg_engagement_distance,
        time_below_50hp_pct=below_50_pct,
        avg_speed=movement.avg_speed,
        hp_samples=hp_samples,
        positions=positions,
        enemy_encounters=dict(enemy_encounters.most_common()),
        resurrections=resurrections,
    )


# ── Recommendation Generator ──────────────────────────────────────────────

def generate_recommendations(maps: list[MapAnalysis]) -> list[str]:
    """
    Generate tactical recommendations for the AI companion based on
    observed patterns across all maps.
    """
    recs: list[str] = []

    # Aggregate stats
    all_damage: Counter[str] = Counter()
    all_weapons: Counter[str] = Counter()
    total_deaths = 0
    total_kills = 0
    death_hp_before: list[int] = []
    total_below_50_samples = 0
    total_hp_samples = 0
    total_resurrections = 0
    behind_damage_tics = 0

    for m in maps:
        for src, dmg in m.damage_sources.items():
            all_damage[src] += dmg
        for w, count in m.weapon_usage.items():
            all_weapons[w] += count
        total_deaths += m.deaths
        total_kills += m.kills
        total_resurrections += m.resurrections
        for de in m.death_events:
            death_hp_before.append(de.hp_before)
        total_below_50_samples += sum(1 for h in m.hp_samples if h < 50)
        total_hp_samples += len(m.hp_samples)

    # 1. Top damage source
    if all_damage:
        top_src, top_dmg = all_damage.most_common(1)[0]
        total_dmg = sum(all_damage.values())
        pct = top_dmg / total_dmg * 100 if total_dmg > 0 else 0
        recs.append(
            f"{top_src} is the #1 damage source ({pct:.0f}%) "
            f"-- bot should prioritize them when they appear"
        )

    # 2. Death HP threshold
    if death_hp_before:
        avg_death_hp = sum(death_hp_before) / len(death_hp_before)
        if avg_death_hp < 50:
            recs.append(
                f"Deaths occurred at avg {avg_death_hp:.0f} HP "
                f"-- call VDR (Retreat) when player drops below {int(avg_death_hp + 15)}"
            )

    # 3. Weapon diversity
    if all_weapons:
        total_samples = sum(all_weapons.values())
        top_weap, top_count = all_weapons.most_common(1)[0]
        top_pct = top_count / total_samples * 100 if total_samples > 0 else 0
        if top_pct > 60:
            recs.append(
                f"{top_weap} dominant ({top_pct:.0f}%) "
                f"-- consider diversifying for range engagements"
            )

    # 4. Time below 50 HP
    if total_hp_samples > 0:
        below_50_pct = total_below_50_samples / total_hp_samples * 100
        if below_50_pct > 25:
            recs.append(
                f"Spent {below_50_pct:.0f}% of time below 50 HP "
                f"-- bot should call VSH (Need health) more aggressively"
            )

    # 5. Resurrections
    if total_resurrections > 0:
        recs.append(
            f"Archvile resurrections detected ({total_resurrections}) "
            f"-- bot must always prioritize Archviles with VAF (Focus fire)"
        )

    # 6. Kill efficiency
    if total_deaths > 0:
        kd = total_kills / total_deaths
        if kd < 20:
            recs.append(
                f"K/D ratio is {kd:.1f} -- focus on survival; "
                f"bot should favor defensive callouts"
            )

    # If we have no specific recs, give a general one
    if not recs:
        recs.append("Solid performance -- maintain current tactics")

    return recs


# ── Report Formatting ──────────────────────────────────────────────────────

def _bar(fraction: float, width: int = BAR_WIDTH) -> str:
    """Render a visual bar: filled blocks + empty blocks."""
    filled = round(fraction * width)
    return "\u2588" * filled + "\u2591" * (width - filled)


def _skill_name(skill: int) -> str:
    """Convert GZDoom skill number to name."""
    names = {1: "ITYTD", 2: "HNTR", 3: "HMP", 4: "UV", 5: "NM"}
    return names.get(skill, f"Skill {skill}")


def format_report(analysis: SessionAnalysis) -> str:
    """Format the full AAR as a printable/saveable string."""
    lines: list[str] = []
    w = 54  # report width

    # ── Header ──
    lines.append("\u2550" * w)
    lines.append("  AFTER ACTION REPORT")
    lines.append(f"  Session: {analysis.timestamp}")
    map_names = ", ".join(m.map_name for m in analysis.maps)
    lines.append(f"  Maps: {map_names}")
    lines.append("\u2550" * w)

    # ── Per-map sections ──
    for m in analysis.maps:
        lines.append("")
        skill_str = f" \u2014 {_skill_name(m.skill)}" if m.skill > 0 else ""
        lines.append(f"{m.map_name} \u2014 Duration: {m.duration_human}{skill_str}")
        lines.append("\u2500" * w)
        lines.append(f"  Kills: {m.kills}    Deaths: {m.deaths}    Damage taken: {m.damage_taken}")

        # Weapon usage
        if m.weapon_usage:
            lines.append("")
            lines.append("  WEAPON USAGE:")
            total_samples = sum(m.weapon_usage.values())
            for weapon, count in list(m.weapon_usage.items())[:6]:
                pct = count / total_samples if total_samples > 0 else 0
                bar = _bar(pct)
                lines.append(f"  {bar} {weapon} ({pct * 100:.0f}%)")

        # Top damage sources
        if m.damage_sources:
            lines.append("")
            lines.append("  TOP DAMAGE SOURCES:")
            total_dmg = sum(m.damage_sources.values())
            for i, (src, dmg) in enumerate(
                sorted(m.damage_sources.items(), key=lambda x: x[1], reverse=True)[:5],
                1,
            ):
                pct = dmg / total_dmg * 100 if total_dmg > 0 else 0
                hits = m.damage_source_counts.get(src, 0)
                lines.append(f"  {i}. {src} \u2014 {dmg} dmg ({pct:.0f}%) [{hits} hits]")

        # Death analysis
        if m.death_events:
            lines.append("")
            lines.append("  DEATH ANALYSIS:")
            for i, de in enumerate(m.death_events, 1):
                lines.append(f"  Death {i} at {de.time_human} \u2014 Killed by {de.killed_by}")
                lines.append(f"    HP was {de.hp_before} before fatal hit")
                lines.append(
                    f"    Position ({de.position[0]:.0f}, {de.position[1]:.0f}), "
                    f"velocity ({de.velocity[0]:.0f}, {de.velocity[1]:.0f})"
                )
                if de.preceding_damage:
                    dmg_list = ", ".join(
                        f"{h.get('dmg', '?')} from {h.get('src', '?')}"
                        for h in de.preceding_damage[-4:]
                    )
                    lines.append(f"    Preceding hits: {dmg_list}")
                lines.append(f"    [{de.insight}]")

        # Tactical patterns
        lines.append("")
        lines.append("  TACTICAL PATTERNS:")
        if m.avg_engagement_distance > 0:
            engage_style = (
                "aggressive" if m.avg_engagement_distance < 400
                else "medium range" if m.avg_engagement_distance < 700
                else "ranged"
            )
            lines.append(
                f"  \u2022 Average engagement distance: "
                f"{m.avg_engagement_distance:.0f} units ({engage_style})"
            )
        lines.append(f"  \u2022 Time spent below 50 HP: {m.time_below_50hp_pct:.0f}% of map")
        lines.append(f"  \u2022 Average movement speed: {m.avg_speed:.1f}")

        if m.resurrections > 0:
            lines.append(f"  \u2022 Archvile resurrections: {m.resurrections}")

    # ── Session Summary ──
    lines.append("")
    lines.append("\u2550" * w)
    lines.append("  SESSION SUMMARY")
    lines.append("\u2550" * w)

    total_time = analysis.total_duration_sec
    time_str = f"{int(total_time // 60)}:{int(total_time % 60):02d}"
    lines.append(f"  Total play time: {time_str}")
    lines.append(
        f"  Total kills: {analysis.total_kills}    "
        f"Total deaths: {analysis.total_deaths}"
    )
    lines.append(f"  Total damage taken: {analysis.total_damage}")

    if analysis.total_deaths > 0:
        kd = analysis.total_kills / analysis.total_deaths
        lines.append(f"  Kill/Death ratio: {kd:.1f}")

    # Cross-session weapon breakdown
    if analysis.all_weapon_usage:
        lines.append("")
        lines.append("  OVERALL WEAPON BREAKDOWN:")
        total_w = sum(analysis.all_weapon_usage.values())
        for weapon, count in sorted(
            analysis.all_weapon_usage.items(), key=lambda x: x[1], reverse=True
        )[:6]:
            pct = count / total_w * 100 if total_w > 0 else 0
            bar = _bar(count / total_w)
            lines.append(f"  {bar} {weapon} ({pct:.0f}%)")

    # Recommendations
    if analysis.recommendations:
        lines.append("")
        lines.append("  LESSONS LEARNED / RECOMMENDATIONS:")
        for rec in analysis.recommendations:
            lines.append(f"  \u2022 {rec}")

    lines.append("")
    lines.append("\u2550" * w)
    return "\n".join(lines)


# ── Main Entry Point ───────────────────────────────────────────────────────

def run_aar(session_dir: Path) -> SessionAnalysis:
    """
    Load a processed session directory and run the full analysis pipeline.
    Returns the SessionAnalysis (and also prints + saves the report).
    """
    session_dir = Path(session_dir)

    # Load summary for metadata
    summary_path = session_dir / "summary.json"
    if summary_path.exists():
        with open(summary_path, "r", encoding="utf-8") as f:
            summary = json.load(f)
    else:
        summary = {}

    # Find all JSONL map files (sorted by filename prefix: 00_, 01_, etc.)
    jsonl_files = sorted(session_dir.glob("*.jsonl"))
    if not jsonl_files:
        print(f"No JSONL event files found in {session_dir}")
        sys.exit(1)

    # Analyze each map
    map_analyses: list[MapAnalysis] = []
    for jf in jsonl_files:
        events = load_events(jf)
        if events:
            analysis = analyze_map_events(events)
            map_analyses.append(analysis)

    if not map_analyses:
        print("No events found in any map file.")
        sys.exit(1)

    # Aggregate stats
    total_kills = sum(m.kills for m in map_analyses)
    total_deaths = sum(m.deaths for m in map_analyses)
    total_damage = sum(m.damage_taken for m in map_analyses)
    total_duration = sum(m.duration_sec for m in map_analyses)

    all_weapons: Counter[str] = Counter()
    all_damage: Counter[str] = Counter()
    for m in map_analyses:
        for w, c in m.weapon_usage.items():
            all_weapons[w] += c
        for s, d in m.damage_sources.items():
            all_damage[s] += d

    # Generate recommendations
    recs = generate_recommendations(map_analyses)

    # Timestamp from directory name or summary
    timestamp = summary.get("processed_at", "")
    if not timestamp:
        # Try to extract from directory name (session_YYYYMMDD_HHMMSS)
        parts = session_dir.name.split("_")
        if len(parts) >= 3:
            try:
                dt = datetime.strptime(f"{parts[1]}_{parts[2]}", "%Y%m%d_%H%M%S")
                timestamp = dt.strftime("%Y-%m-%d %H:%M")
            except (ValueError, IndexError):
                timestamp = session_dir.name
        else:
            timestamp = session_dir.name
    else:
        try:
            dt = datetime.fromisoformat(timestamp)
            timestamp = dt.strftime("%Y-%m-%d %H:%M")
        except ValueError:
            pass

    session_analysis = SessionAnalysis(
        session_dir=session_dir,
        timestamp=timestamp,
        maps=map_analyses,
        total_kills=total_kills,
        total_deaths=total_deaths,
        total_damage=total_damage,
        total_duration_sec=total_duration,
        all_weapon_usage=dict(all_weapons.most_common()),
        all_damage_sources=dict(all_damage.most_common()),
        recommendations=recs,
    )

    # Format and output
    report = format_report(session_analysis)
    print(report)

    # Save as markdown
    now_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    aar_path = session_dir / f"aar_{now_str}.md"
    with open(aar_path, "w", encoding="utf-8") as f:
        f.write("```\n")
        f.write(report)
        f.write("\n```\n")
    print(f"\nAAR saved to: {aar_path}")

    return session_analysis


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python brain/aar_analyzer.py <session_directory>")
        print("  e.g. python brain/aar_analyzer.py data/processed/session_20260412_203000/")
        sys.exit(1)

    session_dir = Path(sys.argv[1])
    if not session_dir.is_dir():
        print(f"Error: {session_dir} is not a directory")
        sys.exit(1)

    run_aar(session_dir)


if __name__ == "__main__":
    main()
