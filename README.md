# Doom Copilot

**An AI co-op companion for Doom (1993) + Project Brutality 3.**

Doom Copilot pairs a ZScript reflex bot (handles movement, aiming, dodging at 35 tics/sec) with an LLM strategic brain (Claude) that makes tactical decisions, issues VGS callouts, and generates after-action reports. The result: an AI teammate that fights alongside you, watches your back, and gets better over time.

> *"Behind you!" — Claude, 0.3 seconds before a Revenant missile hits you in the back of the head*

## Architecture

```
┌─────────────────────────────────────────────────┐
│  GZDoom / UZDoom + Project Brutality 3          │
├─────────────────────────────────────────────────┤
│  ZScript Reflex Layer (35 Hz, in-engine)        │
│  • ZetaBot-derived FSM: Follow/Attack/Flee      │
│  • PB3-aware weapon selection                   │
│  • Threat-prioritized target acquisition        │
│  • Navmesh pathfinding (ZNav)                   │
├─────────────────────────────────────────────────┤
│  Telemetry Logger (in-engine, invisible)        │
│  • Player state, enemy scans, combat events     │
│  • Outputs structured JSON via -logfile         │
├─────────────────────────────────────────────────┤
│  Python Bridge (reads logs, calls Claude)       │
│  • Real-time log tailing (~1 Hz)                │
│  • State snapshots → Claude API                 │
│  • VGS commands → shared file → bot             │
├─────────────────────────────────────────────────┤
│  Claude Brain (strategic layer)                 │
│  • PB3 threat database (all enemy/weapon stats) │
│  • SMITE-style VGS callout system               │
│  • Tactical decisions: push/hold/flank/retreat  │
│  • Post-mission After Action Reports            │
└─────────────────────────────────────────────────┘
```

## Current Status

🚧 **Phase 1: Data Collection & Brain Construction**

- [x] Telemetry logger (ZScript EventHandler for GZDoom)
- [x] Log processor (Python, splits sessions into per-map JSONL + summaries)
- [x] PB3 threat database (parsed from source: all enemies, HP, tiers, resistances)
- [x] PB3 weapon database (parsed from source: all damage values, pellet counts, types)
- [x] VGS decision engine (tactical callout logic)
- [x] AAR analyzer (after-action report generator)
- [ ] ZetaBot fork with PB3 weapon module
- [ ] Python ↔ GZDoom bridge (real-time log tail + command injection)
- [ ] Claude brain integration (API calls with state snapshots)
- [ ] Voice callouts (TTS for VGS commands)

## Project Structure

```
doom-copilot/
├── logger/                    # GZDoom telemetry mod
│   ├── hearth-logger/         #   ZScript EventHandler + MAPINFO
│   └── process_logs.py        #   Session log → JSONL + summaries
├── brain/                     # AI decision-making
│   ├── pb3_data/              #   Generated enemy & weapon databases
│   ├── threat_db.py           #   Threat assessment from PB3 stats
│   ├── vgs_engine.py          #   VGS callout decision logic
│   └── aar_analyzer.py        #   After Action Report generator
├── extractor/                 # PB3 source code parser
│   └── parse_pb3.py           #   Extracts stats → JSON databases
└── docs/                      # Design documents
    ├── ARCHITECTURE.md         #   Full system design
    ├── VGS_COMMANDS.md         #   Callout command reference
    └── ZETABOT_ASSESSMENT.md   #   Bot framework evaluation
```

## VGS Command System

Inspired by SMITE's Voice Game System — a fixed menu of tactical callouts that both the human player and AI companion can issue. Fixed vocabulary means faster decisions and mappable audio cues.

| Code | Callout | Trigger |
|------|---------|---------|
| VAA | "Attack!" | Push forward |
| VAF | "Focus fire!" | Priority target (Archvile, boss) |
| VEB | "Behind you!" | Rear threat detected |
| VEH | "Heavy incoming!" | T4+ enemy in scan range |
| VDR | "Retreat!" | Tactical withdrawal |
| VDC | "Cover me!" | Need suppression |
| VSH | "Need health!" | Low HP |
| VTG | "Go go go!" | Breach/push |

[Full command reference →](docs/VGS_COMMANDS.md)

## Quick Start

### Prerequisites
- [GZDoom](https://zdoom.org/downloads) 4.2+ (or UZDoom, LZDoom)
- [Project Brutality 3](https://github.com/pa1nki113r/Project_Brutality)
- Python 3.10+
- Doom 2 IWAD (`doom2.wad`)

### 1. Record Gameplay Data
Load the logger alongside PB3 — it's invisible and records everything:
```bash
gzdoom -iwad doom2.wad -file ProjectBrutality/ logger/hearth-logger/ -logfile session.log
```

### 2. Process Logs
```bash
python logger/process_logs.py
```

### 3. Generate AAR
```bash
python brain/aar_analyzer.py data/processed/session_*/
```

## Roadmap

- **Phase 1** (current): Data collection, PB3 knowledge base, offline analysis tools
- **Phase 2**: ZetaBot fork with PB3 weapon module, basic co-op companion
- **Phase 3**: Claude brain integration, real-time VGS callouts
- **Phase 4**: Voice comms (TTS), personality, learning from AARs
- **Phase 5** (dream): Squad tactics — R6 Vegas 2 style breach-and-clear with multiple AI operators

## Credits

- [Project Brutality](https://github.com/pa1nki113r/Project_Brutality) by pa1nki113r
- [ZetaBot](https://github.com/zeta-group/ZetaBot) by the Zeta Group
- [ZNav](https://github.com/disasteroftheuniverse/zdoom-pathfinding) by disasteroftheuniverse
- [GZDoom](https://github.com/ZDoom/gzdoom) by the ZDoom team
- AI brain powered by [Claude](https://anthropic.com) (Anthropic)

## License

MIT
