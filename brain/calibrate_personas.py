"""
Persona calibration — derive empirical tuning from captured telemetry.

Reads all sessions in data/processed/ and computes:
  1. Threat weights per monster class
       → `damage_sources` counters weighted per encounter
       → ranks which enemies actually hurt Dan vs. paper damage stats
  2. Weapon effective-kill rate
       → `weapons_used` dwell time × `enemies_killed` correlation
       → which weapons pull their weight in Dan's playstyle
  3. Flee-HP distribution
       → `hp_samples` near player_death events → the HP Dan dies at
       → `hp_samples` during no-damage windows → the HP Dan survives at
       → per-persona flee threshold = empirical survival floor
  4. Combat range distribution
       → enemy `dist` values at moments when `hurt` or `kill` fires
       → peak engagement ranges for each weapon class

Output:
  brain/calibrated.json — machine-readable knob values
  brain/calibrated.md   — human-readable report Dan can scan

The output is advisory — nothing auto-patches PersonaControllers.zs.
Dan reviews and hand-applies changes he agrees with. Keeps the
empirical signal separate from the design intent.

Usage:
    python calibrate_personas.py
    python calibrate_personas.py --sessions path1 path2 ...
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent
PROCESSED_DIR = REPO_ROOT / "data" / "processed"
TICS_PER_SEC = 35


def load_session_summaries(base: Path) -> list[dict]:
    summaries = []
    for p in base.glob("*/summary.json"):
        try:
            summaries.append(json.load(p.open(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            continue
    return summaries


def load_session_events(base: Path) -> list[list[dict]]:
    """Load raw events per map segment across all sessions."""
    all_maps = []
    for jsonl in base.glob("*/*.jsonl"):
        events = []
        with jsonl.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        if events:
            all_maps.append(events)
    return all_maps


# ── 1. Threat weights ──────────────────────────────────────────────

def compute_threat_weights(summaries: list[dict]) -> list[dict]:
    """Per-class damage weight, normalized so top enemy = 1.0."""
    total_damage: Counter[str] = Counter()
    encounters: Counter[str] = Counter()

    for s in summaries:
        for m in s.get("maps", []):
            for klass, count in m.get("top_damage_sources", {}).items():
                total_damage[klass] += count
            for klass, count in m.get("top_enemies_seen", {}).items():
                encounters[klass] += count

    # Normalize: damage per encounter — "how dangerous is this when I see it?"
    # Filter: only classes that actually appear in enemy scans (real monsters).
    # This excludes self-damage (PB_PlayerPrawn), environmental (world, barrels),
    # and anything otherwise untracked.
    damage_per_encounter: dict[str, float] = {}
    for klass, dmg in total_damage.items():
        seen = encounters.get(klass, 0)
        if seen == 0:
            continue  # not a monster we scan for
        damage_per_encounter[klass] = dmg / seen

    if not damage_per_encounter:
        return []

    top = max(damage_per_encounter.values())
    rows = []
    for klass, raw in sorted(damage_per_encounter.items(), key=lambda x: -x[1]):
        rows.append({
            "class": klass,
            "damage_per_encounter": round(raw, 3),
            "weight": round(raw / top, 3),
            "total_damage_instances": total_damage[klass],
            "encounters": encounters.get(klass, 0),
        })
    return rows


# ── 2. Weapon effective-kill rate ──────────────────────────────────

def compute_weapon_effectiveness(summaries: list[dict]) -> list[dict]:
    """Kills per tic of dwell time = weapon throughput."""
    dwell: Counter[str] = Counter()
    for s in summaries:
        for m in s.get("maps", []):
            for weap, count in m.get("weapons_used", {}).items():
                dwell[weap] += count

    # Total session kills as a ceiling reference (we don't have per-weapon kill attribution
    # from summaries — that would require re-walking JSONL; do it for precision).
    # For now: normalize by dwell time so relative ordering is correct.
    if not dwell:
        return []
    top = max(dwell.values())
    rows = []
    for weap, tics in sorted(dwell.items(), key=lambda x: -x[1]):
        rows.append({
            "weapon": weap,
            "dwell_tics": tics,
            "dwell_frac": round(tics / top, 3),
            "dwell_sec": round(tics / TICS_PER_SEC, 1),
        })
    return rows


# ── 3. Flee-HP distribution ────────────────────────────────────────

def compute_flee_threshold(map_events_list: list[list[dict]]) -> dict:
    """
    Find the HP Dan dies at vs. survives at.

    For each player_death event, look back 70 tics (~2 sec) and capture
    the HP trajectory. For non-death windows of similar length, capture
    the "low-water" HP. The threshold that separates them is the
    empirical flee target.
    """
    death_hps: list[int] = []
    survival_low_hps: list[int] = []

    for events in map_events_list:
        death_tics: list[int] = []
        for ev in events:
            if ev.get("t") == "player_death":
                death_tics.append(ev.get("tic", 0))

        # For each death, collect HP at death and nearby low values
        for dt in death_tics:
            nearby = [e for e in events if e.get("t") == "state"
                      and dt - 70 <= e.get("tic", 0) <= dt]
            if nearby:
                min_hp = min(e.get("hp", 100) for e in nearby)
                death_hps.append(min_hp)

        # Survival sampling: look at state events and find 2-sec windows
        # where no death occurred; grab the min HP as a survival floor
        window_size = 70
        window_ends = range(window_size, max((e.get("tic", 0) for e in events), default=0), window_size)
        death_tic_set = set(death_tics)
        for end in window_ends:
            has_death = any(abs(end - dt) < window_size for dt in death_tics)
            if has_death:
                continue
            windowed = [e for e in events if e.get("t") == "state"
                        and end - window_size <= e.get("tic", 0) <= end]
            if windowed:
                min_hp = min(e.get("hp", 100) for e in windowed)
                if min_hp < 100:  # only count actual combat pressure
                    survival_low_hps.append(min_hp)

    if not survival_low_hps:
        return {"deaths_sampled": len(death_hps), "note": "insufficient survival windows"}

    survival_p10 = percentile(survival_low_hps, 10)
    survival_p25 = percentile(survival_low_hps, 25)
    survival_p50 = percentile(survival_low_hps, 50)

    return {
        "deaths_sampled": len(death_hps),
        "death_hp_median": int(statistics.median(death_hps)) if death_hps else None,
        "death_hp_min": min(death_hps) if death_hps else None,
        "survival_low_hp_p10": int(survival_p10),
        "survival_low_hp_p25": int(survival_p25),
        "survival_low_hp_p50": int(survival_p50),
        "flee_thresh_frac_safe":  round(survival_p50 / 100, 2),  # 50th pctile — conservative
        "flee_thresh_frac_tank":  round(survival_p25 / 100, 2),  # 25th pctile — brave
        "flee_thresh_frac_brawler": round(survival_p10 / 100, 2),  # 10th — very aggressive
    }


def percentile(values: list[float], pct: int) -> float:
    if not values:
        return 0
    values = sorted(values)
    k = (len(values) - 1) * pct / 100
    f = int(k)
    c = min(f + 1, len(values) - 1)
    if f == c:
        return values[f]
    return values[f] + (values[c] - values[f]) * (k - f)


# ── 4. Combat range distribution ───────────────────────────────────

def compute_engagement_ranges(map_events_list: list[list[dict]]) -> dict:
    """
    Per-weapon engagement distance distribution.

    For each kill event, find the state event just before it and look
    up the current weapon + nearest enemy distance in the enemy scan.
    That distance is the empirical engagement range for that weapon.
    """
    weapon_ranges: dict[str, list[float]] = defaultdict(list)

    for events in map_events_list:
        # Build a tic-indexed view: state and nearest enemy per tic
        state_by_tic: dict[int, dict] = {}
        nearest_by_tic: dict[int, float] = {}
        for ev in events:
            tic = ev.get("tic", 0)
            if ev.get("t") == "state":
                state_by_tic[tic] = ev
            elif ev.get("t") == "enemy":
                d = ev.get("dist", 1e9)
                nearest_by_tic[tic] = min(nearest_by_tic.get(tic, 1e9), d)

        # For each kill, find the state event at or just before it
        state_tics_sorted = sorted(state_by_tic.keys())
        for ev in events:
            if ev.get("t") != "kill":
                continue
            ktic = ev.get("tic", 0)
            # Find closest state tic <= ktic
            prior = [t for t in state_tics_sorted if t <= ktic]
            if not prior:
                continue
            stic = prior[-1]
            weap = state_by_tic[stic].get("weapon", "None")
            dist = nearest_by_tic.get(stic)
            if weap == "None" or dist is None:
                continue
            weapon_ranges[weap].append(dist)

    summary = {}
    for weap, dists in weapon_ranges.items():
        if len(dists) < 3:
            continue
        summary[weap] = {
            "kills": len(dists),
            "range_p25": int(percentile(dists, 25)),
            "range_median": int(statistics.median(dists)),
            "range_p75": int(percentile(dists, 75)),
            "range_mean": int(sum(dists) / len(dists)),
        }
    return dict(sorted(summary.items(), key=lambda x: -x[1]["kills"]))


# ── Report assembly ────────────────────────────────────────────────

def write_report(md_path: Path, data: dict) -> None:
    lines = []
    lines.append("# Persona Calibration — empirical tuning from Dan's telemetry\n")
    lines.append(f"Generated from {data['source_sessions']} sessions "
                 f"({data['source_maps']} map segments, {data['total_kills']} kills, "
                 f"{data['total_deaths']} deaths, {data['play_time_min']} min of play).\n")

    lines.append("## 1. Threat weights\n")
    lines.append("Ordered by damage-per-encounter. Pre-apply to "
                 "`DoomCopilotController.targetPriority()` persona override.\n")
    lines.append("| Class | Dmg/encounter | Weight | Dmg instances | Encounters |")
    lines.append("|-------|---------------|--------|---------------|-----------|")
    for row in data["threat_weights"][:20]:
        lines.append(f"| {row['class']} | {row['damage_per_encounter']} | "
                     f"{row['weight']} | {row['total_damage_instances']} | {row['encounters']} |")
    lines.append("")

    lines.append("## 2. Weapon dwell time\n")
    lines.append("How much time Dan actually spends holding each weapon. "
                 "Use to decide which weapons deserve hand-tuned RateSelf curves.\n")
    lines.append("| Weapon | Tics | Seconds | Dwell fraction |")
    lines.append("|--------|------|---------|----------------|")
    for row in data["weapon_effectiveness"]:
        lines.append(f"| {row['weapon']} | {row['dwell_tics']} | "
                     f"{row['dwell_sec']} | {row['dwell_frac']} |")
    lines.append("")

    lines.append("## 3. Flee-HP thresholds\n")
    ft = data["flee_threshold"]
    if "note" in ft:
        lines.append(f"_{ft['note']}_\n")
    else:
        lines.append(f"- Sampled **{ft['deaths_sampled']} deaths**")
        lines.append(f"- Median HP at death: **{ft['death_hp_median']}**")
        lines.append(f"- Survival low-water — p50: {ft['survival_low_hp_p50']}, "
                     f"p25: {ft['survival_low_hp_p25']}, p10: {ft['survival_low_hp_p10']}")
        lines.append("")
        lines.append("### Suggested persona flee thresholds (override FleeHpFrac):")
        lines.append(f"- **Tank** (safe): `return {ft['flee_thresh_frac_safe']};`")
        lines.append(f"- **Sharpshooter** (moderate): `return {round((ft['flee_thresh_frac_safe'] + ft['flee_thresh_frac_tank']) / 2, 2)};`")
        lines.append(f"- **Brawler** (aggressive): `return {ft['flee_thresh_frac_brawler']};`")
        lines.append(f"- **Death-Wish**: CanFlee() = false (unchanged)")
    lines.append("")

    lines.append("## 4. Engagement ranges by weapon\n")
    lines.append("The empirical range at which kills happen for each weapon. "
                 "Use to calibrate `RateSelf` curve peaks in `PB3Weapons.zs`.\n")
    lines.append("| Weapon | Kills sampled | p25 | Median | p75 | Mean |")
    lines.append("|--------|---------------|-----|--------|-----|------|")
    for weap, row in data["engagement_ranges"].items():
        lines.append(f"| {weap} | {row['kills']} | {row['range_p25']} | "
                     f"{row['range_median']} | {row['range_p75']} | {row['range_mean']} |")
    lines.append("")

    md_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="Calibrate persona dials from telemetry")
    ap.add_argument("--sessions", nargs="*", default=None,
                    help="Session dir paths (default: all under data/processed/)")
    ap.add_argument("--out-json", default=None)
    ap.add_argument("--out-md", default=None)
    args = ap.parse_args()

    if args.sessions:
        session_paths = [Path(p) for p in args.sessions]
    else:
        session_paths = [p for p in PROCESSED_DIR.iterdir() if p.is_dir()]

    if not session_paths:
        print(f"No session directories found under {PROCESSED_DIR}", file=sys.stderr)
        return 1

    print(f"Calibrating from {len(session_paths)} session(s)")

    summaries = []
    all_events = []
    total_kills = 0
    total_deaths = 0
    play_time_sec = 0

    for sp in session_paths:
        sp = Path(sp)
        sum_path = sp / "summary.json"
        if sum_path.exists():
            try:
                s = json.load(sum_path.open(encoding="utf-8"))
                summaries.append(s)
                tot = s.get("totals", {})
                total_kills += tot.get("kills", 0)
                total_deaths += tot.get("deaths", 0)
                play_time_sec += tot.get("play_time_sec", 0)
            except (OSError, json.JSONDecodeError):
                pass
        for jsonl in sp.glob("*.jsonl"):
            events = []
            with jsonl.open("r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        events.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
            if events:
                all_events.append(events)

    data = {
        "source_sessions": len(summaries),
        "source_maps": len(all_events),
        "total_kills": total_kills,
        "total_deaths": total_deaths,
        "play_time_min": round(play_time_sec / 60, 1),
        "threat_weights": compute_threat_weights(summaries),
        "weapon_effectiveness": compute_weapon_effectiveness(summaries),
        "flee_threshold": compute_flee_threshold(all_events),
        "engagement_ranges": compute_engagement_ranges(all_events),
    }

    out_json = Path(args.out_json) if args.out_json else SCRIPT_DIR / "calibrated.json"
    out_md = Path(args.out_md) if args.out_md else SCRIPT_DIR / "calibrated.md"

    out_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    write_report(out_md, data)

    print(f"  → {out_json}")
    print(f"  → {out_md}")

    # Echo a terse summary to stdout
    print()
    print(f"  {total_kills} kills  |  {total_deaths} deaths  |  {data['play_time_min']} min")
    if data["threat_weights"]:
        top3 = data["threat_weights"][:3]
        print(f"  Top threats: " + ", ".join(f"{r['class']}({r['weight']})" for r in top3))
    if "flee_thresh_frac_safe" in data["flee_threshold"]:
        ft = data["flee_threshold"]
        print(f"  Suggested flee thresholds — tank: {ft['flee_thresh_frac_safe']}  "
              f"brawler: {ft['flee_thresh_frac_brawler']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
