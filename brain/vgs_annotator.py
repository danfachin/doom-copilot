"""
VGS Annotator — human-in-the-loop labeling of game state snapshots.

Walks a processed map JSONL, shows you the state summary at each window,
and lets you label with a VGS code + optional tactical tag. Output is a JSONL
that becomes the few-shot example set for the Claude brain's prompt.

Usage:
    python vgs_annotator.py --map data/processed/session_.../01_MAP13.jsonl
    python vgs_annotator.py --map ...  --window 70 --stride 140
    python vgs_annotator.py --map ...  --resume          # skip already-labeled tics

Commands at each snapshot:
    VEB VEH VDR VAF VEF VEL VER VSH VSA VAA ...  — assign this VGS code
    .                                             — no callout (silence was correct)
    s <tag>                                       — set tactical tag (aggressive/defensive/hold/push/regroup/conserve_ammo)
    /  <note>                                     — freeform note on this snapshot
    b                                             — back one snapshot
    ?                                             — show VGS reference
    q                                             — save and quit
    Enter                                         — same as . (silence)
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from claude_brain import (  # noqa: E402
    TICS_PER_SEC,
    build_state_from_window,
    iter_windows,
    load_events,
    render_state_for_prompt,
)
from vgs_engine import VGS  # noqa: E402


TACTICAL_TAGS = {"aggressive", "defensive", "conserve_ammo", "push", "hold", "regroup"}


def print_reference() -> None:
    print("\n=== VGS Reference ===")
    by_cat = {"Attack": [], "Defend": [], "Enemy": [], "Status": [], "Tactical": []}
    cat_prefix = {"A": "Attack", "D": "Defend", "E": "Enemy", "S": "Status", "T": "Tactical"}
    for code, cmd in VGS.items():
        cat = cat_prefix.get(code[1], "Other")
        by_cat.setdefault(cat, []).append((code, cmd.text))
    for cat, items in by_cat.items():
        print(f"  {cat}:")
        for code, text in items:
            print(f"    {code}  {text}")
    print(f"\n  Tactical tags: {', '.join(sorted(TACTICAL_TAGS))}")
    print(f"  Commands: . (silence)  s <tag>  / <note>  b (back)  q (quit)  ? (this help)\n")


def load_existing(out_path: Path) -> dict[int, dict]:
    """Load existing annotations, keyed by tic. Allows resuming."""
    if not out_path.exists():
        return {}
    out: dict[int, dict] = {}
    with out_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
                out[row["tic"]] = row
            except (json.JSONDecodeError, KeyError):
                continue
    return out


def save_all(out_path: Path, annotations: dict[int, dict]) -> None:
    """Write annotations sorted by tic."""
    with out_path.open("w", encoding="utf-8") as f:
        for tic in sorted(annotations.keys()):
            f.write(json.dumps(annotations[tic]) + "\n")


def prompt_for_label(snapshot_index: int, total: int, tic: int, current: dict | None) -> dict | None:
    """Interactive prompt. Returns annotation dict, or None for 'back'."""
    hint = ""
    if current:
        prev = current.get("callout") or "."
        tag = current.get("tactical") or "-"
        note = current.get("note") or ""
        hint = f" [prev: {prev} tag={tag} note={note!r}]"

    ann = dict(current) if current else {"tic": tic, "sec": round(tic / TICS_PER_SEC, 1)}

    while True:
        try:
            raw = input(
                f"[{snapshot_index+1}/{total}] tic={tic} ({tic/TICS_PER_SEC:.1f}s){hint} > "
            ).strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return {"__quit__": True}

        if raw == "" or raw == ".":
            ann["callout"] = None
            return ann
        if raw == "q":
            return {"__quit__": True}
        if raw == "b":
            return None  # sentinel for "back"
        if raw == "?":
            print_reference()
            continue
        if raw.startswith("s "):
            tag = raw[2:].strip().lower()
            if tag in TACTICAL_TAGS or tag == "":
                ann["tactical"] = tag or None
                print(f"  tactical = {ann['tactical']}")
            else:
                print(f"  ! unknown tag, expected one of: {', '.join(sorted(TACTICAL_TAGS))}")
            continue
        if raw.startswith("/ "):
            ann["note"] = raw[2:].strip()
            print(f"  note = {ann['note']!r}")
            continue
        # Assume it's a VGS code
        code = raw.upper()
        if code in VGS:
            ann["callout"] = code
            ann["callout_text"] = VGS[code].text
            return ann
        print(f"  ! unknown: {raw}  (type ? for reference)")


def main() -> int:
    ap = argparse.ArgumentParser(description="VGS callout annotator")
    ap.add_argument("--map", required=True)
    ap.add_argument("--window", type=int, default=70, help="window tics (default 70 = 2s)")
    ap.add_argument("--stride", type=int, default=140, help="stride tics (default 140 = 4s)")
    ap.add_argument("--resume", action="store_true", help="skip already-labeled snapshots")
    ap.add_argument("--skip-silence", action="store_true",
                    help="skip windows with no enemies and no damage")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    map_path = Path(args.map)
    if not map_path.exists():
        print(f"Not found: {map_path}", file=sys.stderr)
        return 1

    out_path = Path(args.out) if args.out else map_path.with_suffix(".annotations.jsonl")
    events = load_events(map_path)
    existing = load_existing(out_path)

    window_ends = list(iter_windows(events, args.window, args.stride))
    print(f"Map: {map_path.name}  events={len(events)}  windows={len(window_ends)}  "
          f"existing={len(existing)}  out={out_path.name}")
    print("Type ? for command reference, q to save and quit.\n")

    # Build snapshot list (skipping silent if requested, skipping labeled if resume)
    snapshots = []
    for end_tic in window_ends:
        gs = build_state_from_window(events, end_tic, args.window)
        if args.skip_silence and not gs.enemies and gs.recent_damage_taken == 0:
            continue
        if args.resume and end_tic in existing:
            continue
        snapshots.append((end_tic, gs))

    if not snapshots:
        print("Nothing to label (all snapshots skipped or already labeled).")
        return 0

    i = 0
    while i < len(snapshots):
        end_tic, gs = snapshots[i]
        print("\n" + "=" * 70)
        print(render_state_for_prompt(gs))
        result = prompt_for_label(i, len(snapshots), end_tic, existing.get(end_tic))
        if result is None:
            i = max(0, i - 1)
            continue
        if result.get("__quit__"):
            break
        existing[end_tic] = result
        # Save after every annotation — survives Ctrl+C
        save_all(out_path, {k: v for k, v in existing.items() if not v.get("__quit__")})
        i += 1

    # Final save (ensure nothing transient sneaks in)
    save_all(out_path, {k: v for k, v in existing.items() if not v.get("__quit__")})
    labeled = sum(1 for v in existing.values() if not v.get("__quit__"))
    print(f"\nSaved {labeled} annotations to {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
