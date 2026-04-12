#!/usr/bin/env python3
"""
PB3 Source Extractor -- Parses Project Brutality 3 monster and weapon definitions
from both DECORATE (.dec) and ZScript (.zc/.zsc/.zs) source files.

Produces enemies.json and weapons.json for the doom-copilot AI companion.
"""

from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# ---------------------------------------------------------------------------
# Tier mapping from directory names
# ---------------------------------------------------------------------------
TIER_MAP = {
    "T1-Grunts":   (1, "T1-Grunts"),
    "T1-Imps":     (1, "T1-Imps"),
    "T2-Pinkies":  (2, "T2-Pinkies"),
    "T3-Arachnos": (3, "T3-Arachnos"),
    "T3-Fats":     (3, "T3-Fats"),
    "T3-Floaters": (3, "T3-Floaters"),
    "T3-Revies":   (3, "T3-Revies"),
    "T4-Nobles":   (4, "T4-Nobles"),
    "T4-Viles":    (4, "T4-Viles"),
    "Tz-Bosses":   (5, "Tz-Bosses"),
    "Tz-Frozen":   (5, "Tz-Frozen"),
    "Tz-Shrinks":  (5, "Tz-Shrinks"),
    # ZScript directories (no tier prefix) -- map by monster type
    "ZombieMen":    (1, "T1-Grunts"),
    "Sergeants":    (1, "T1-Grunts"),
    "Chaingunner":  (1, "T1-Grunts"),
    "Imps":         (1, "T1-Imps"),
    "Pinkies":      (2, "T2-Pinkies"),
    "Arachnotrons": (3, "T3-Arachnos"),
    "Mancubi":      (3, "T3-Fats"),
    "Cacodemons":   (3, "T3-Floaters"),
    "LostSouls":    (3, "T3-Floaters"),
    "Elementals":   (3, "T3-Floaters"),
    "Revenants":    (3, "T3-Revies"),
    "Knights":      (4, "T4-Nobles"),
    "ArchViles":    (4, "T4-Viles"),
    "Cyberdemons":  (5, "Tz-Bosses"),
    "Special":      (5, "Tz-Bosses"),
}

# Damage factor types that are internal/meta -- not useful for gameplay analysis
SKIP_DAMAGE_FACTORS = {
    "crush", "gibreremoving", "gibremoving", "teleportremover", "killme",
    "avoid", "causeobjectstosplash", "blood", "blueblood", "greenblood",
    "dontcallthebaron", "baronbarrelcall",
}

# Class name substrings that indicate non-combat actors (gib parts, death variants, etc.)
JUNK_SUBSTRINGS = [
    "LastStand", "Dying", "Dead", "Brutalized", "Stomped", "Curbstomp",
    "Thrown", "FlyingCorpse", "Frozen", "Shrink", "Blackhole", "LilImp",
    "LilDemon", "LilBaron", "LilKnight", "LilCaco", "NoHead", "NoArm",
    "Blasted", "Stomach", "Exploded", "Gibbed", "Skinned", "_alt",
    "FacingFront", "HelmetGib", "HeadGib", "Chaingun_Pickup",
    "SwitchMode", "BossTarget", "EmptyTarget", "LostLeg", "LostHead",
    "ChainsawMarine", "CurbstompedMarine", "MonsterTargetCheck",
    "AlertAfterDeath", "DeathAnim",
]

# Flags we care about extracting
INTERESTING_FLAGS = {
    "BOSS", "ISMONSTER", "DONTRIP", "NORADIUSDMG", "QUICKTORETALIATE",
    "MISSILEMORE", "MISSILEEVENMORE", "BOSSDEATH", "DONTMORPH",
    "DONTHURTSPECIES", "DONTHARMSPECIES", "DONTHARMCLASS",
    "NOICEDEATH", "NOBLOOD",
}


def is_junk_class(class_name: str) -> bool:
    """Return True if the class name indicates a non-combat actor."""
    for sub in JUNK_SUBSTRINGS:
        if sub.lower() in class_name.lower():
            return True
    return False


def read_file_text(path: Path) -> str:
    """Read a file, trying utf-8 first then latin-1."""
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="latin-1")


# ---------------------------------------------------------------------------
# DECORATE parser
# ---------------------------------------------------------------------------

def find_decorate_actors(text: str) -> List[Tuple[str, str, str]]:
    """
    Find all ACTOR definitions in DECORATE text.
    Returns list of (class_name, parent_class, actor_body).
    """
    results = []
    # Match: ACTOR ClassName : ParentClass { ... }
    # or:    ACTOR ClassName { ... }
    pattern = re.compile(
        r'ACTOR\s+(\w+)\s*(?::\s*(\w+))?\s*(?://[^\n]*)?\s*\{',
        re.IGNORECASE
    )
    for m in pattern.finditer(text):
        class_name = m.group(1)
        parent_class = m.group(2) or ""
        # Find the matching closing brace
        body_start = m.end()
        body = extract_braced_body(text, body_start)
        if body is not None:
            results.append((class_name, parent_class, body))
    return results


def extract_braced_body(text: str, start: int) -> Optional[str]:
    """Extract text from start position to matching closing brace."""
    depth = 1
    i = start
    while i < len(text) and depth > 0:
        ch = text[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
        i += 1
    if depth == 0:
        return text[start:i - 1]
    return None


def parse_decorate_monster(
    class_name: str, parent_class: str, body: str,
    source_file: str, tier: int, tier_label: str
) -> Optional[Dict[str, Any]]:
    """Parse a DECORATE actor definition into a monster record."""
    # Skip obvious non-combat actors by name
    if is_junk_class(class_name):
        return None

    body_lower = body.lower()
    full_text = body

    # Must look like a monster
    is_monster = False
    monster_parents = {
        "pb_monster", "pb_rev", "pb_vile", "fatso", "cyberdemon",
        "spidermastermind", "arachnotron", "revenant", "archvile",
    }
    if parent_class.lower() in monster_parents:
        is_monster = True
    if re.search(r'\bmonster\b', body_lower):
        is_monster = True
    if re.search(r'^\s*health\s+\d', body_lower, re.MULTILINE):
        is_monster = True

    if not is_monster:
        return None

    # Extract health
    health_match = re.search(r'^\s*health\s+(\d+)', body_lower, re.MULTILINE)
    if not health_match:
        return None
    health = int(health_match.group(1))

    # Skip tiny-health actors (gib parts, effects)
    if health < 20:
        return None

    # Extract speed
    speed = None
    speed_match = re.search(r'^\s*speed\s+(\d+)', body_lower, re.MULTILINE)
    if speed_match:
        speed = int(speed_match.group(1))

    # Extract damage factors
    damage_factors = {}  # type: Dict[str, float]
    for dm in re.finditer(r'damagefactor\s+"(\w+)"\s*,?\s*([\d.]+)', body, re.IGNORECASE):
        dtype = dm.group(1)
        dval = float(dm.group(2))
        if dtype.lower() not in SKIP_DAMAGE_FACTORS:
            damage_factors[dtype] = dval

    # Extract flags
    flags = []  # type: List[str]
    for fm in re.finditer(r'\+(\w+)', full_text):
        flag = fm.group(1).upper()
        if flag in INTERESTING_FLAGS:
            flags.append(flag)

    # Check for Missile/Melee states
    has_missile = bool(re.search(r'^\s*Missile:', body, re.MULTILINE | re.IGNORECASE))
    has_melee = bool(re.search(r'^\s*Melee:', body, re.MULTILINE | re.IGNORECASE))

    # Extract PB_Monster hitbox damage multipliers
    hitbox_mults = {}  # type: Dict[str, float]
    mon_dmg_match = re.search(
        r'PB_Monster\.MonDMGMult\s+([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)',
        body
    )
    if mon_dmg_match:
        hitbox_mults = {
            "head": float(mon_dmg_match.group(1)),
            "torso": float(mon_dmg_match.group(2)),
            "arm": float(mon_dmg_match.group(3)),
            "low_torso": float(mon_dmg_match.group(4)),
            "dick": float(mon_dmg_match.group(5)),
            "leg": float(mon_dmg_match.group(6)),
        }

    # Extract hitbox position thresholds
    hitbox_positions = {}  # type: Dict[str, float]
    pos_match = re.search(
        r'PB_Monster\.MonPosHB\s+([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)',
        body
    )
    if pos_match:
        hitbox_positions = {
            "head_threshold": float(pos_match.group(1)),
            "torso_threshold": float(pos_match.group(2)),
            "dick_threshold": float(pos_match.group(3)),
            "leg_threshold": float(pos_match.group(4)),
        }

    # Extract PB_Monster boolean properties
    pb_flags = []  # type: List[str]
    for prop_match in re.finditer(r'PB_Monster\.(\w+)\s+(\w+)', body):
        prop_name = prop_match.group(1)
        prop_val = prop_match.group(2).lower()
        if prop_name in ("CanIRoll", "CanIFallback", "CanIReload", "CanISuppress"):
            if prop_val in ("true", "1"):
                pb_flags.append(prop_name)

    # Extract species
    species = None  # type: Optional[str]
    species_match = re.search(r'^\s*species\s+"(\w+)"', body, re.MULTILINE | re.IGNORECASE)
    if species_match:
        species = species_match.group(1)

    return {
        "class_name": class_name,
        "parent_class": parent_class,
        "health": health,
        "speed": speed,
        "tier": tier,
        "tier_label": tier_label,
        "damage_factors": damage_factors,
        "hitbox_mults": hitbox_mults,
        "hitbox_positions": hitbox_positions,
        "has_missile": has_missile,
        "has_melee": has_melee,
        "flags": sorted(set(flags)),
        "pb_flags": sorted(set(pb_flags)),
        "species": species,
        "source_file": source_file,
    }


# ---------------------------------------------------------------------------
# ZScript parser
# ---------------------------------------------------------------------------

def find_zscript_classes(text: str) -> List[Tuple[str, str, str]]:
    """
    Find all class definitions in ZScript text.
    Returns list of (class_name, parent_class, class_body).
    """
    results = []
    pattern = re.compile(
        r'class\s+(\w+)\s*:\s*(\w+)(?:\s+\w+)*\s*\{',
        re.IGNORECASE
    )
    for m in pattern.finditer(text):
        class_name = m.group(1)
        parent_class = m.group(2)
        body_start = m.end()
        body = extract_braced_body(text, body_start)
        if body is not None:
            results.append((class_name, parent_class, body))
    return results


def parse_zscript_monster(
    class_name: str, parent_class: str, body: str,
    source_file: str, tier: int, tier_label: str
) -> Optional[Dict[str, Any]]:
    """Parse a ZScript class definition into a monster record."""
    # Skip obvious non-combat actors by name
    if is_junk_class(class_name):
        return None

    body_lower = body.lower()

    # Skip abstract base classes
    if "abstract" in body_lower[:50]:
        return None

    # Determine if this is a monster
    monster_parents = {
        "pb_monster", "pb_rev", "pb_vile", "fatso", "cyberdemon",
        "spidermastermind", "arachnotron", "revenant", "archvile",
    }
    is_monster = parent_class.lower() in monster_parents
    if re.search(r'\bmonster\b', body_lower):
        is_monster = True

    if not is_monster:
        return None

    # Extract health (ZScript uses semicolons)
    health = None
    health_match = re.search(r'\bhealth\s+(\d+)\s*;', body_lower)
    if health_match:
        health = int(health_match.group(1))

    if health is None:
        return None
    if health < 20:
        return None

    # Extract speed
    speed = None
    speed_match = re.search(r'\bspeed\s+(\d+)\s*;', body_lower)
    if speed_match:
        speed = int(speed_match.group(1))

    # Extract damage factors
    damage_factors = {}  # type: Dict[str, float]
    for dm in re.finditer(r'damagefactor\s+"(\w+)"\s*,?\s*([\d.]+)\s*;', body, re.IGNORECASE):
        dtype = dm.group(1)
        dval = float(dm.group(2))
        if dtype.lower() not in SKIP_DAMAGE_FACTORS:
            damage_factors[dtype] = dval

    # Extract flags
    flags = []  # type: List[str]
    for fm in re.finditer(r'\+(\w+)', body):
        flag = fm.group(1).upper()
        if flag in INTERESTING_FLAGS:
            flags.append(flag)

    # Check for Missile/Melee states
    has_missile = bool(re.search(r'^\s*Missile:', body, re.MULTILINE | re.IGNORECASE))
    has_melee = bool(re.search(r'^\s*Melee:', body, re.MULTILINE | re.IGNORECASE))

    # Extract hitbox damage multipliers
    hitbox_mults = {}  # type: Dict[str, float]
    mon_dmg_match = re.search(
        r'PB_Monster\.MonDMGMult\s+([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)',
        body
    )
    if mon_dmg_match:
        hitbox_mults = {
            "head": float(mon_dmg_match.group(1)),
            "torso": float(mon_dmg_match.group(2)),
            "arm": float(mon_dmg_match.group(3)),
            "low_torso": float(mon_dmg_match.group(4)),
            "dick": float(mon_dmg_match.group(5)),
            "leg": float(mon_dmg_match.group(6)),
        }

    # Extract hitbox position thresholds
    hitbox_positions = {}  # type: Dict[str, float]
    pos_match = re.search(
        r'PB_Monster\.MonPosHB\s+([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)',
        body
    )
    if pos_match:
        hitbox_positions = {
            "head_threshold": float(pos_match.group(1)),
            "torso_threshold": float(pos_match.group(2)),
            "dick_threshold": float(pos_match.group(3)),
            "leg_threshold": float(pos_match.group(4)),
        }

    # Extract PB_Monster boolean properties
    pb_flags = []  # type: List[str]
    for prop_match in re.finditer(r'PB_Monster\.(\w+)\s+(\w+)', body):
        prop_name = prop_match.group(1)
        prop_val = prop_match.group(2).lower()
        if prop_name in ("CanIRoll", "CanIFallback", "CanIReload", "CanISuppress"):
            if prop_val in ("true", "1"):
                pb_flags.append(prop_name)

    # Extract species
    species = None  # type: Optional[str]
    species_match = re.search(r'\bspecies\s+"(\w+)"\s*;', body, re.IGNORECASE)
    if species_match:
        species = species_match.group(1)

    return {
        "class_name": class_name,
        "parent_class": parent_class,
        "health": health,
        "speed": speed,
        "tier": tier,
        "tier_label": tier_label,
        "damage_factors": damage_factors,
        "hitbox_mults": hitbox_mults,
        "hitbox_positions": hitbox_positions,
        "has_missile": has_missile,
        "has_melee": has_melee,
        "flags": sorted(set(flags)),
        "pb_flags": sorted(set(pb_flags)),
        "species": species,
        "source_file": source_file,
    }


# ---------------------------------------------------------------------------
# Weapon / Projectile parser (ZScript -- that's where the data lives)
# ---------------------------------------------------------------------------

def parse_zscript_weapon(
    class_name: str, parent_class: str, body: str, source_file: str
) -> Optional[Dict[str, Any]]:
    """Parse a ZScript projectile definition into a weapon/projectile record."""
    body_lower = body.lower()

    # Must have BaseDamage
    dmg_match = re.search(r'PB_Projectile\.BaseDamage\s+(\d+)', body, re.IGNORECASE)
    if not dmg_match:
        return None

    base_damage = int(dmg_match.group(1))

    # Extract damage type
    damage_type = None  # type: Optional[str]
    dt_match = re.search(r'\bDamagetype\s+"(\w+)"\s*;', body, re.IGNORECASE)
    if dt_match:
        damage_type = dt_match.group(1)

    # Extract ripper count
    ripper_count = None  # type: Optional[int]
    rc_match = re.search(r'PB_Projectile\.RipperCount\s+(\d+)', body, re.IGNORECASE)
    if rc_match:
        ripper_count = int(rc_match.group(1))

    # Extract penetration count
    penetration_count = None  # type: Optional[int]
    pc_match = re.search(r'PB_Projectile\.PenetrationCount\s+(\d+)', body, re.IGNORECASE)
    if pc_match:
        penetration_count = int(pc_match.group(1))

    # Detect special properties
    special = []  # type: List[str]
    if re.search(r'\+.*RIPPER', body, re.IGNORECASE) or (ripper_count and ripper_count > 1):
        special.append("ripper")
    if penetration_count and penetration_count > 0:
        special.append("penetration")
    if re.search(r'OMNIDIRECTIONAL', body, re.IGNORECASE):
        special.append("omnidirectional")
    if re.search(r'SMALLIMPACT', body, re.IGNORECASE):
        special.append("small_caliber")
    if re.search(r'WHIZCRACK', body, re.IGNORECASE):
        special.append("whiz_crack")
    if re.search(r'NOCRITICALS', body, re.IGNORECASE):
        special.append("no_criticals")
    if re.search(r'A_Explode', body, re.IGNORECASE):
        special.append("explosive")
    if re.search(r'BOUNCE', body, re.IGNORECASE):
        special.append("bouncing")

    # Determine caliber from class name
    caliber = infer_caliber(class_name)

    # Detect if it's a pellet (shotgun)
    is_pellet = "pellet" in class_name.lower()

    # Detect speed override
    speed = None  # type: Optional[int]
    speed_match = re.search(r'\bspeed\s+(\d+)\s*;', body_lower)
    if speed_match:
        speed = int(speed_match.group(1))

    return {
        "class_name": class_name,
        "parent_class": parent_class,
        "base_damage": base_damage,
        "damage_type": damage_type,
        "caliber": caliber,
        "ripper_count": ripper_count,
        "penetration_count": penetration_count,
        "is_pellet": is_pellet,
        "speed": speed,
        "special": sorted(set(special)),
        "source_file": source_file,
    }


def infer_caliber(class_name: str) -> Optional[str]:
    """Infer caliber/ammo type from projectile class name."""
    name = class_name.upper()
    caliber_patterns = {
        "12GA": "12ga",
        "10GA": "10ga",
        "8GA": "8ga",
        "9X19": "9x19mm",
        "45ACP": ".45 ACP",
        "500SW": ".500 S&W",
        "50AE": ".50 AE",
        "556X45": "5.56x45mm",
        "762X51": "7.62x51mm",
        "792X57": "7.92x57mm",
        "MGNAIL": "nail",
        "JAVELIN": "javelin",
        "MICROMISSILE": "micro_missile",
        "RIFLE": "rifle",
        "PISTOL": "pistol",
        "MAGNUM": "magnum",
        "SHOTPELLET": "shotgun",
        "SHOTSLUG": "slug",
        "NAZI": "rifle",
        "MINIGUN": "minigun",
        "MASTERMIND": "minigun_he",
        "MONSTERTRACER": "tracer",
    }
    for pattern, cal in caliber_patterns.items():
        if pattern in name:
            return cal
    return None


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def find_monster_files(pb3_path: Path) -> List[Tuple[Path, str]]:
    """Find all monster definition files. Returns (path, format) tuples."""
    files = []  # type: List[Tuple[Path, str]]

    # DECORATE files in actors/Monsters/
    actors_monsters = pb3_path / "actors" / "Monsters"
    if actors_monsters.exists():
        for dirpath, dirnames, filenames in os.walk(actors_monsters):
            for fn in filenames:
                if fn.endswith(".dec") or ("." not in fn and not fn.startswith(".")):
                    fp = Path(dirpath) / fn
                    files.append((fp, "decorate"))

    # ZScript files in zscript/Monsters/
    zscript_monsters = pb3_path / "zscript" / "Monsters"
    if zscript_monsters.exists():
        for dirpath, dirnames, filenames in os.walk(zscript_monsters):
            for fn in filenames:
                if fn.endswith((".zc", ".zsc", ".zs")):
                    fp = Path(dirpath) / fn
                    files.append((fp, "zscript"))

    return files


def find_weapon_files(pb3_path: Path) -> List[Path]:
    """Find all weapon/projectile definition files."""
    files = []  # type: List[Path]

    # ZScript weapon projectiles
    projectiles_dir = pb3_path / "zscript" / "Weapons" / "Projectiles"
    if projectiles_dir.exists():
        for fn in os.listdir(projectiles_dir):
            if fn.endswith((".zsc", ".zs", ".zc")):
                files.append(projectiles_dir / fn)

    return files


def get_tier_from_path(file_path: Path) -> Tuple[int, str]:
    """Determine tier from the file's directory path."""
    parts = file_path.parts
    for part in parts:
        if part in TIER_MAP:
            return TIER_MAP[part]
    return (0, "Unknown")


def relative_source(file_path: Path, pb3_path: Path) -> str:
    """Get relative path string for source_file field."""
    try:
        return str(file_path.relative_to(pb3_path)).replace("\\", "/")
    except ValueError:
        return str(file_path).replace("\\", "/")


# ---------------------------------------------------------------------------
# Main extraction
# ---------------------------------------------------------------------------

def extract_enemies(pb3_path: Path) -> List[Dict[str, Any]]:
    """Extract all monster definitions from PB3 source."""
    enemies = []  # type: List[Dict[str, Any]]
    seen_classes = set()  # type: Set[str]

    for file_path, fmt in find_monster_files(pb3_path):
        text = read_file_text(file_path)
        tier, tier_label = get_tier_from_path(file_path)
        rel_path = relative_source(file_path, pb3_path)

        if fmt == "decorate":
            actors = find_decorate_actors(text)
            for cname, pclass, body in actors:
                if cname in seen_classes:
                    continue
                monster = parse_decorate_monster(
                    cname, pclass, body, rel_path, tier, tier_label
                )
                if monster:
                    enemies.append(monster)
                    seen_classes.add(cname)
        else:  # zscript
            classes = find_zscript_classes(text)
            for cname, pclass, body in classes:
                if cname in seen_classes:
                    continue
                monster = parse_zscript_monster(
                    cname, pclass, body, rel_path, tier, tier_label
                )
                if monster:
                    enemies.append(monster)
                    seen_classes.add(cname)

    # Sort by tier, then class name
    enemies.sort(key=lambda e: (e["tier"], e["class_name"]))
    return enemies


def extract_weapons(pb3_path: Path) -> List[Dict[str, Any]]:
    """Extract all weapon/projectile definitions from PB3 source."""
    weapons = []  # type: List[Dict[str, Any]]
    seen_classes = set()  # type: Set[str]

    for file_path in find_weapon_files(pb3_path):
        text = read_file_text(file_path)
        rel_path = relative_source(file_path, pb3_path)

        classes = find_zscript_classes(text)
        for cname, pclass, body in classes:
            if cname in seen_classes:
                continue
            weapon = parse_zscript_weapon(cname, pclass, body, rel_path)
            if weapon:
                weapons.append(weapon)
                seen_classes.add(cname)

    # Sort by base damage descending
    weapons.sort(key=lambda w: (-w["base_damage"], w["class_name"]))
    return weapons


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Parse Project Brutality 3 source into enemy/weapon JSON databases"
    )
    parser.add_argument(
        "--pb3-path",
        default=r"D:\Users\Dan\games\DOOM\Project_Brutality-master",
        help="Path to PB3 source root",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Output directory for JSON files (default: ../brain/pb3_data/ relative to this script)",
    )
    args = parser.parse_args()

    pb3_path = Path(args.pb3_path)
    if not pb3_path.exists():
        print("ERROR: PB3 path not found: {}".format(pb3_path))
        return

    if args.output_dir:
        output_dir = Path(args.output_dir)
    else:
        output_dir = Path(__file__).resolve().parent.parent / "brain" / "pb3_data"
    output_dir.mkdir(parents=True, exist_ok=True)

    print("PB3 source:  {}".format(pb3_path))
    print("Output dir:  {}".format(output_dir))
    print()

    # ---- Extract enemies ----
    print("=== Extracting enemies ===")
    enemies = extract_enemies(pb3_path)
    enemies_path = output_dir / "enemies.json"
    with open(str(enemies_path), "w", encoding="utf-8") as f:
        json.dump(enemies, f, indent=2, ensure_ascii=False)

    # Print summary
    tier_counts = {}  # type: Dict[int, int]
    for e in enemies:
        t = e["tier"]
        tier_counts[t] = tier_counts.get(t, 0) + 1

    print("  Total enemies: {}".format(len(enemies)))
    for t in sorted(tier_counts):
        label = "Tier {}".format(t)
        for e in enemies:
            if e["tier"] == t:
                label = e["tier_label"]
                break
        print("    Tier {} ({}): {}".format(t, label, tier_counts[t]))

    print("  Written to: {}".format(enemies_path))
    print()

    # Show a few examples
    print("  Sample entries:")
    for e in enemies[:3]:
        spd = e['speed'] if e['speed'] is not None else '?'
        print("    {:<30s} HP={:5d}  Spd={:>3}  Tier={}".format(
            e['class_name'], e['health'], spd, e['tier']))
    if len(enemies) > 6:
        print("    ...")
        for e in enemies[-3:]:
            spd = e['speed'] if e['speed'] is not None else '?'
            print("    {:<30s} HP={:5d}  Spd={:>3}  Tier={}".format(
                e['class_name'], e['health'], spd, e['tier']))
    print()

    # ---- Extract weapons ----
    print("=== Extracting weapons ===")
    weapons = extract_weapons(pb3_path)
    weapons_path = output_dir / "weapons.json"
    with open(str(weapons_path), "w", encoding="utf-8") as f:
        json.dump(weapons, f, indent=2, ensure_ascii=False)

    print("  Total weapons/projectiles: {}".format(len(weapons)))
    print("  Written to: {}".format(weapons_path))
    print()

    # Show weapon summary
    print("  Top damage projectiles:")
    for w in weapons[:5]:
        dtype = w['damage_type'] or 'default'
        cal = w['caliber'] or '?'
        print("    {:<35s} DMG={:4d}  Type={:<15s}  Cal={}".format(
            w['class_name'], w['base_damage'], dtype, cal))
    print()

    print("  Small arms:")
    small = [w for w in weapons if w["base_damage"] < 30]
    for w in small[:5]:
        dtype = w['damage_type'] or 'default'
        cal = w['caliber'] or '?'
        print("    {:<35s} DMG={:4d}  Type={:<15s}  Cal={}".format(
            w['class_name'], w['base_damage'], dtype, cal))

    print()
    print("Done!")


if __name__ == "__main__":
    main()
