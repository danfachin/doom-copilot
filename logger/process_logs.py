"""
Hearth Doom Log Processor
Reads raw GZDoom logfiles, extracts [HL] telemetry lines,
splits by map, and generates session summaries for Claude analysis.

Usage:
    python process_logs.py                  # process all unprocessed logs
    python process_logs.py session_xyz.log  # process a specific log
"""

import json
import sys
import re
from pathlib import Path
from collections import Counter, defaultdict
from datetime import datetime

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent
DATA_DIR = REPO_ROOT / "data"
PROCESSED_DIR = DATA_DIR / "processed"
HL_PATTERN = re.compile(r"\[HL\](.+)")
TICS_PER_SEC = 35.0


def extract_events(logfile: Path) -> list[dict]:
    """Pull all [HL] JSON events from a raw GZDoom logfile."""
    events = []
    with open(logfile, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = HL_PATTERN.search(line)
            if not m:
                continue
            try:
                events.append(json.loads(m.group(1)))
            except json.JSONDecodeError:
                continue  # skip malformed lines
    return events


def split_by_map(events: list[dict]) -> list[list[dict]]:
    """Split event stream into per-map segments using map_start/map_end markers."""
    maps = []
    current = []
    for ev in events:
        current.append(ev)
        if ev.get("t") == "map_end":
            maps.append(current)
            current = []
    # Capture trailing events (crash / quit without map_end)
    if current:
        maps.append(current)
    return maps


def analyze_map(events: list[dict]) -> dict:
    """Generate summary stats for a single map run."""
    map_name = "unknown"
    skill = -1
    max_tic = 0
    kills = 0
    deaths = 0
    damage_taken = 0
    damage_sources = Counter()
    enemies_seen = Counter()
    enemies_killed = Counter()
    weapons_used = Counter()
    resurrections = 0

    hp_samples = []
    positions = []

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
            w = ev.get("weapon", "None")
            if w != "None":
                weapons_used[w] += 1

        elif t == "enemy":
            enemies_seen[ev.get("class", "?")] += 1

        elif t == "kill":
            enemies_killed[ev.get("class", "?")] += 1

        elif t == "hurt":
            damage_taken += ev.get("dmg", 0)
            damage_sources[ev.get("src", "?")] += 1

        elif t == "player_death":
            deaths += 1

        elif t == "revived":
            resurrections += 1

    duration_sec = max_tic / TICS_PER_SEC if max_tic > 0 else 0
    avg_hp = sum(hp_samples) / len(hp_samples) if hp_samples else 0

    # Movement: total distance traveled
    dist_traveled = 0.0
    for i in range(1, len(positions)):
        dx = positions[i][0] - positions[i - 1][0]
        dy = positions[i][1] - positions[i - 1][1]
        dist_traveled += (dx**2 + dy**2) ** 0.5

    return {
        "map": map_name,
        "skill": skill,
        "duration_sec": round(duration_sec, 1),
        "duration_human": f"{int(duration_sec // 60)}:{int(duration_sec % 60):02d}",
        "kills": kills,
        "deaths": deaths,
        "damage_taken": damage_taken,
        "avg_hp": round(avg_hp, 1),
        "distance_traveled": round(dist_traveled, 0),
        "resurrections": resurrections,
        "top_damage_sources": dict(damage_sources.most_common(10)),
        "top_enemies_seen": dict(enemies_seen.most_common(15)),
        "top_enemies_killed": dict(enemies_killed.most_common(15)),
        "weapons_used": dict(weapons_used.most_common(10)),
    }


def process_logfile(logfile: Path) -> dict:
    """Process a single raw logfile into per-map JSONL + session summary."""
    print(f"  Processing: {logfile.name}")
    events = extract_events(logfile)

    if not events:
        print(f"    No [HL] events found — skipping")
        return {}

    print(f"    {len(events)} events extracted")

    # Session output directory
    stem = logfile.stem  # e.g. session_20260412_203000
    session_dir = PROCESSED_DIR / stem
    session_dir.mkdir(parents=True, exist_ok=True)

    # Split by map and write per-map JSONL
    map_segments = split_by_map(events)
    summaries = []

    for i, seg in enumerate(map_segments):
        # Determine map name from segment
        map_name = "unknown"
        for ev in seg:
            if ev.get("map"):
                map_name = ev["map"]
                break

        # Write raw events as JSONL
        jsonl_file = session_dir / f"{i:02d}_{map_name}.jsonl"
        with open(jsonl_file, "w", encoding="utf-8") as f:
            for ev in seg:
                f.write(json.dumps(ev) + "\n")

        # Generate map summary
        summary = analyze_map(seg)
        summary["events_file"] = jsonl_file.name
        summary["event_count"] = len(seg)
        summaries.append(summary)

        dur = summary["duration_human"]
        kills = summary["kills"]
        deaths = summary["deaths"]
        print(f"    Map {i}: {map_name} — {dur}, {kills} kills, {deaths} deaths")

    # Write session summary
    session_summary = {
        "session_file": logfile.name,
        "processed_at": datetime.now().isoformat(),
        "total_events": len(events),
        "maps_played": len(summaries),
        "maps": summaries,
        "totals": {
            "kills": sum(m["kills"] for m in summaries),
            "deaths": sum(m["deaths"] for m in summaries),
            "damage_taken": sum(m["damage_taken"] for m in summaries),
            "play_time_sec": round(sum(m["duration_sec"] for m in summaries), 1),
        },
    }

    summary_file = session_dir / "summary.json"
    with open(summary_file, "w", encoding="utf-8") as f:
        json.dump(session_summary, f, indent=2)

    print(f"    Summary → {summary_file.relative_to(DATA_DIR)}")
    return session_summary


def find_unprocessed() -> list[Path]:
    """Find raw logfiles that haven't been processed yet."""
    if not DATA_DIR.exists():
        return []

    processed_stems = set()
    if PROCESSED_DIR.exists():
        processed_stems = {d.name for d in PROCESSED_DIR.iterdir() if d.is_dir()}

    raw_logs = sorted(DATA_DIR.glob("session_*.log"))
    return [f for f in raw_logs if f.stem not in processed_stems]


def main():
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)

    if len(sys.argv) > 1:
        # Process specific file(s)
        targets = [DATA_DIR / f for f in sys.argv[1:]]
    else:
        # Process all unprocessed
        targets = find_unprocessed()

    if not targets:
        print("No unprocessed logfiles found in doom/data/")
        print("Play some Doom with play.bat first!")
        return

    print(f"=== Hearth Doom Log Processor ===")
    print(f"Found {len(targets)} logfile(s) to process\n")

    all_summaries = []
    for logfile in targets:
        if not logfile.exists():
            print(f"  Not found: {logfile}")
            continue
        summary = process_logfile(logfile)
        if summary:
            all_summaries.append(summary)
        print()

    # Write cross-session index
    if all_summaries:
        index_file = PROCESSED_DIR / "index.json"

        # Load existing index if present
        existing = []
        if index_file.exists():
            with open(index_file, "r") as f:
                existing = json.load(f)

        existing_files = {s["session_file"] for s in existing}
        for s in all_summaries:
            if s["session_file"] not in existing_files:
                existing.append(
                    {
                        "session_file": s["session_file"],
                        "processed_at": s["processed_at"],
                        "maps_played": s["maps_played"],
                        "totals": s["totals"],
                    }
                )

        with open(index_file, "w") as f:
            json.dump(existing, f, indent=2)

        total_kills = sum(s["totals"]["kills"] for s in all_summaries)
        total_deaths = sum(s["totals"]["deaths"] for s in all_summaries)
        total_time = sum(s["totals"]["play_time_sec"] for s in all_summaries)
        print(f"=== Done ===")
        print(f"Sessions: {len(all_summaries)}")
        print(f"Kills: {total_kills}  Deaths: {total_deaths}")
        print(f"Play time: {int(total_time // 60)}m {int(total_time % 60)}s")


if __name__ == "__main__":
    main()
