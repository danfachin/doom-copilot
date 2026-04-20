"""
Claude Brain — strategic layer prototype for Doom Copilot.

Walks a processed map JSONL, builds state snapshots at fixed intervals,
and asks Claude for a VGS callout + tactical intent per snapshot.
Output is a JSONL of (snapshot, claude_response, rule_engine_response) rows
so you can compare the LLM brain against vgs_engine.py.

Usage:
    python claude_brain.py --map data/processed/session_.../02_MAP12.jsonl
    python claude_brain.py --map ...  --dry-run              # print prompts, don't call API
    python claude_brain.py --map ... --window 70 --stride 35  # tics (35/sec)
    python claude_brain.py --map ... --model claude-sonnet-4-6

Requires ANTHROPIC_API_KEY for real runs. Use --dry-run to iterate without burning tokens.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter, deque
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from vgs_engine import (  # noqa: E402
    VGS,
    EnemySnapshot,
    GameState,
    PlayerState,
    VGSEngine,
    classify_tier,
)

TICS_PER_SEC = 35
DEFAULT_MODEL = "claude-opus-4-7"

SYSTEM_PROMPT = """You are the strategic brain for an AI co-op companion in GZDoom + Project Brutality 3. Your job: watch a state snapshot and decide whether to issue a VGS callout (a single tactical voice command) and what tactical intent to set for the reflex-layer bot.

## Output format

Return a single JSON object, no prose, no markdown fences:

{
  "callout": "VEB" | "VEH" | ... | null,
  "tactical": "aggressive" | "defensive" | "conserve_ammo" | "push" | "hold" | "regroup" | null,
  "priority_target": "<enemy class name>" | null,
  "reasoning": "<one sentence, for telemetry only>"
}

Use `null` for callout when the right call is silence. Do NOT emit a callout just to fill space.

## VGS vocabulary (the ONLY valid callouts)

Attack: VAA (attack), VAL (attack left), VAR (attack right), VAF (focus fire — Archvile / boss)
Defend: VDD (hold here), VDR (retreat), VDC (cover me)
Enemy:  VEF (enemy ahead), VEB (behind you), VEL (left), VER (right), VEH (heavy incoming)
Status: VSR (ready), VSH (need health), VSA (need ammo)
Tactical: VTF (follow me), VTS (stay put), VTG (go go go), VTK (objective here)

## Priority hierarchy

1. VEB (rear threat within damage range) — overrides everything, the single most important callout.
2. VAF (Archvile in scan range — they resurrect, ALWAYS priority).
3. VEH (tier-4+ enemy entering the fight) or VDR (HP critical + multiple threats).
4. VEL/VER (flanking threats off-axis from current facing).
5. VSH (HP below survivable threshold) or VSA (primary weapon dry).
6. VEF / VAA / VTG (ambient push calls when the situation is calm enough).
7. Silence (null) when nothing useful.

## Tactical tag semantics

- `aggressive`: reduce follow distance, engage freely, press the fight
- `defensive`: increase follow distance, flee earlier, conserve HP
- `conserve_ammo`: prefer melee/pistol, hold heavy ammo
- `push`: move toward a direction or objective
- `hold`: stay at current position, do not advance
- `regroup`: fall back to the player's position
- `null`: no change, keep current tactical stance

The tactical tag is durable — set one only when the situation genuinely calls for a shift. Do not toggle it every snapshot.

## Enemy tier shorthand in snapshots

T1 = grunt (zombie/imp, 70–115 HP)
T2 = midweight (pinky, ~200 HP)
T3 = heavy (caco/revenant/mancubus/arach, 300–900 HP)
T4 = elite (baron/hell knight/archvile, 650–1300 HP)
BOSS = cyber/mastermind (5000+ HP)"""


def build_state_from_window(events: list[dict], window_end_tic: int, window_len: int) -> GameState:
    """Build a GameState from events in [window_end_tic - window_len, window_end_tic]."""
    window_start = window_end_tic - window_len

    player = PlayerState()
    enemies_by_class_dist: dict[tuple[str, float, float], EnemySnapshot] = {}
    recent_damage = 0
    recent_deaths = 0
    recent_resurrections = 0
    last_state_tic = -1
    map_name = ""

    for ev in events:
        tic = ev.get("tic", 0)
        if tic > window_end_tic:
            break
        if tic < window_start:
            continue

        t = ev.get("t")
        if t == "state":
            if tic > last_state_tic:
                last_state_tic = tic
                player = PlayerState(
                    px=ev.get("px", 0), py=ev.get("py", 0), pz=ev.get("pz", 0),
                    angle=ev.get("pa", 0), hp=ev.get("hp", 100), armor=ev.get("ar", 0),
                    weapon=ev.get("weapon", "None"), ammo=ev.get("ammo", 0),
                    kills=ev.get("kills", 0), vx=ev.get("vx", 0), vy=ev.get("vy", 0),
                )
                map_name = ev.get("map", map_name)
                enemies_by_class_dist.clear()
        elif t == "enemy" and tic == last_state_tic:
            key = (ev.get("class", "?"), round(ev.get("dist", 0)), round(ev.get("angle", 0)))
            enemies_by_class_dist[key] = EnemySnapshot(
                class_name=ev.get("class", "?"),
                distance=ev.get("dist", 0),
                angle=ev.get("angle", 0),
                hp=ev.get("hp", 0),
                maxhp=ev.get("maxhp", 0),
                state=ev.get("state", "idle"),
            )
        elif t == "hurt":
            recent_damage += ev.get("dmg", 0)
        elif t == "player_death":
            recent_deaths += 1
        elif t == "revived":
            recent_resurrections += 1

    return GameState(
        player=player,
        enemies=sorted(enemies_by_class_dist.values(), key=lambda e: e.distance),
        tic=window_end_tic,
        map_name=map_name,
        recent_damage_taken=recent_damage,
        recent_deaths=recent_deaths,
        recent_resurrections=recent_resurrections,
    )


def render_state_for_prompt(gs: GameState) -> str:
    """Produce a compact, LLM-friendly text description of the game state."""
    p = gs.player
    lines = []
    lines.append(f"[map] {gs.map_name}  tic={gs.tic}  ({gs.tic / TICS_PER_SEC:.1f}s)")
    lines.append(
        f"[player] hp={p.hp} armor={p.armor} weapon={p.weapon} ammo={p.ammo} "
        f"kills={p.kills} speed={p.speed:.0f} facing={p.angle:.0f}°"
    )
    if gs.recent_damage_taken:
        lines.append(f"[recent] damage_taken_last_window={gs.recent_damage_taken}")
    if gs.recent_resurrections:
        lines.append(f"[recent] resurrections={gs.recent_resurrections}  (Archvile active!)")
    if gs.recent_deaths:
        lines.append(f"[recent] player_deaths={gs.recent_deaths}")

    if not gs.enemies:
        lines.append("[enemies] none visible within 2048u")
        return "\n".join(lines)

    lines.append(f"[enemies] {len(gs.enemies)} visible:")
    for i, e in enumerate(gs.enemies[:10]):
        tier = classify_tier(e.maxhp, e.class_name).name
        rear = "  **REAR**" if abs(e.angle) > 135 else ""
        flank = ""
        if 45 < abs(e.angle) <= 135:
            flank = "  **LEFT**" if e.angle > 0 else "  **RIGHT**"
        lines.append(
            f"  {i+1}. {e.class_name} [{tier}] hp={e.hp}/{e.maxhp} "
            f"dist={e.distance:.0f} angle={e.angle:+.0f}° state={e.state}{rear}{flank}"
        )
    if len(gs.enemies) > 10:
        lines.append(f"  ...and {len(gs.enemies) - 10} more")
    return "\n".join(lines)


def build_messages(gs: GameState) -> list[dict]:
    user_msg = (
        "Current game state:\n\n"
        + render_state_for_prompt(gs)
        + "\n\nDecide: callout, tactical, priority_target, reasoning. Return JSON only."
    )
    return [{"role": "user", "content": user_msg}]


def call_claude(messages: list[dict], model: str) -> dict:
    try:
        import anthropic
    except ImportError:
        raise RuntimeError("pip install anthropic")

    client = anthropic.Anthropic()
    # System is cached — static across every snapshot in this run.
    resp = client.messages.create(
        model=model,
        max_tokens=400,
        system=[{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
        messages=messages,
    )
    text = resp.content[0].text.strip()
    # Strip code fences if model wrapped anyway
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
        text = text.strip()
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        parsed = {"error": f"parse_failed: {exc}", "raw": text}
    parsed["_usage"] = {
        "input_tokens": resp.usage.input_tokens,
        "output_tokens": resp.usage.output_tokens,
        "cache_read": getattr(resp.usage, "cache_read_input_tokens", 0),
        "cache_creation": getattr(resp.usage, "cache_creation_input_tokens", 0),
    }
    return parsed


def run_rule_engine(gs: GameState, engine: VGSEngine, now: float) -> dict | None:
    result = engine.decide(gs, now=now)
    if not result:
        return None
    return {
        "callout": result.code,
        "text": result.text,
        "priority": result.priority.name,
        "reasoning": result.reason,
    }


def load_events(jsonl_path: Path) -> list[dict]:
    events = []
    with jsonl_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def iter_windows(events: list[dict], window_tics: int, stride_tics: int):
    """Yield window_end_tic for each snapshot, starting after the first window fills."""
    if not events:
        return
    max_tic = max(ev.get("tic", 0) for ev in events)
    t = window_tics
    while t <= max_tic:
        yield t
        t += stride_tics


def main() -> int:
    ap = argparse.ArgumentParser(description="Claude strategic brain prototype")
    ap.add_argument("--map", required=True, help="Path to processed map JSONL")
    ap.add_argument("--window", type=int, default=70, help="Window size in tics (default 70 = 2s)")
    ap.add_argument("--stride", type=int, default=70, help="Stride in tics (default 70 = 2s)")
    ap.add_argument("--model", default=DEFAULT_MODEL, help=f"Claude model (default {DEFAULT_MODEL})")
    ap.add_argument("--dry-run", action="store_true", help="Print prompts, skip API calls")
    ap.add_argument("--limit", type=int, default=0, help="Stop after N snapshots (0 = all)")
    ap.add_argument("--out", default=None, help="Output JSONL path (default: alongside input)")
    ap.add_argument("--skip-silence", action="store_true",
                    help="Skip windows with no enemies, no damage, no combat context")
    args = ap.parse_args()

    map_path = Path(args.map)
    if not map_path.exists():
        print(f"Not found: {map_path}", file=sys.stderr)
        return 1

    events = load_events(map_path)
    print(f"Loaded {len(events)} events from {map_path.name}")

    engine = VGSEngine()
    out_path = Path(args.out) if args.out else map_path.with_suffix(".brain.jsonl")

    n_snapshots = 0
    n_called = 0
    skipped = 0
    total_usage = Counter()

    with out_path.open("w", encoding="utf-8") as out_f:
        for end_tic in iter_windows(events, args.window, args.stride):
            gs = build_state_from_window(events, end_tic, args.window)

            if args.skip_silence and not gs.enemies and gs.recent_damage_taken == 0:
                skipped += 1
                continue

            n_snapshots += 1
            sim_now = end_tic / TICS_PER_SEC
            rule_out = run_rule_engine(gs, engine, now=sim_now)

            row = {
                "tic": end_tic,
                "sec": round(end_tic / TICS_PER_SEC, 1),
                "state_summary": render_state_for_prompt(gs),
                "rule_engine": rule_out,
            }

            if args.dry_run:
                print(f"\n--- snapshot tic={end_tic} ({end_tic / TICS_PER_SEC:.1f}s) ---")
                print(row["state_summary"])
                print(f"rule_engine: {rule_out}")
            else:
                try:
                    claude_out = call_claude(build_messages(gs), args.model)
                    row["claude"] = claude_out
                    if "_usage" in claude_out:
                        for k, v in claude_out["_usage"].items():
                            total_usage[k] += v
                    if claude_out.get("callout"):
                        n_called += 1
                    print(
                        f"tic={end_tic:6d}  rule={(rule_out or {}).get('callout', '—'):4}"
                        f"  claude={claude_out.get('callout', '—') or '—':4}"
                        f"  tag={claude_out.get('tactical') or '—'}"
                    )
                except Exception as exc:
                    row["claude_error"] = str(exc)
                    print(f"tic={end_tic}  ERROR: {exc}", file=sys.stderr)

            out_f.write(json.dumps(row) + "\n")

            if args.limit and n_snapshots >= args.limit:
                break

    print(f"\n=== done ===")
    print(f"Snapshots processed: {n_snapshots}  (skipped silent: {skipped})")
    if not args.dry_run:
        print(f"Claude callouts issued: {n_called}  ({n_called / max(n_snapshots, 1) * 100:.0f}%)")
        print(f"Tokens: in={total_usage['input_tokens']}  out={total_usage['output_tokens']}  "
              f"cache_read={total_usage['cache_read']}  cache_create={total_usage['cache_creation']}")
    print(f"Output: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
