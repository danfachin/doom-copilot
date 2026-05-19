// PB3 weapon module for Doom Copilot bots.
//
// Covers the top-12 weapons Dan actually uses (from telemetry-ranked
// weapons_used counters across 5 captured sessions):
//   PB_Shotgun      3594 tics equipped
//   PB_Minigun      1734
//   PB_DMR          1456
//   PB_SSG          1294
//   PB_AutoShotgun   944
//   PB_Carbine       938
//   PB_Revolver      909
//   PB_RocketLauncher 796
//   PB_Pistol        678
//   PB_Flamethrower  515
//   PB_Chainsaw      479
//   PB_BFG9000       253
//
// Each ZetaWeapon subclass's IsPickupOf uses a class-name pattern so
// PB3's variants within a slot (e.g. 4 shotgun variants) all map to
// the same Zeta class with slot-appropriate ratings and synthetic
// fire behavior. Long-tail weapons fall through to ZetaPB3Generic.
//
// Fire() uses ZetaBullet.FireBullets for hitscan and SpawnMissileAngle
// for projectiles — same pattern as vanilla ZetaDoomWeapons. Damage
// values calibrated against PB3 source (BulletDef.*.zsc projectile
// BaseDamage × PB_FireBullets pellet/round counts per weapon's Fire
// state). ZetaBullet treats damage at face value — no vanilla
// random(1..3) multiplier — so values are passed slightly under PB3
// actual to compensate for bots bypassing the reaction-time/aim
// disadvantages the Pilot has when wielding the same gun.

// ── Shotgun family ────────────────────────────────────────────
// PB_Shotgun, PB_AutoShotgun, PB_SSG, PB_QuadSG
class ZetaPB3Shotgun : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 10571428;
        ZetaWeapon.MinAmmo 1;
        ZetaWeapon.AmmoType "PB_Shell";
        ZetaWeapon.WeaponName "PB3 Shotgun";
        Obituary "%o caught %k's PB3 shell.";
    }

    override bool IsPickupOf(Weapon other)
    {
        name cls = other.GetClassName();
        return cls == 'PB_Shotgun' || cls == 'PB_Autoshotgun'
            || cls == 'PB_SSG'     || cls == 'PB_QuadSG';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Peak at close-mid (128-512u), fall off beyond
        double d = shooter.Distance2D(target);
        if (d < 64) return 500;   // still decent point-blank
        return 1200 / (1 + sqrt(d / 2));
    }

    // PB3 source: actors/weapons/Slot3/SHOTGUN.dec:1025
    //   PB_FireBullets("PB_12GAPellet", 9, ...)
    // Projectile: zscript/Weapons/Projectiles/BulletDef.Shell.zsc:1
    //   PB_12GAPellet.BaseDamage = 15
    // PB3 actual: 9 pellets × 15 = 135 effective per shot.
    // SSG variant fires 20 × PB_10GAPellet (18) = 360; Autoshotgun
    // 8 × 15 = 120; QuadSG single barrel 12 × PB_8GAPellet (17) = 204.
    // Bot fire: averaged across variants and trimmed ~30% for the
    // accuracy edge bots get from synthetic Fire(). 9 × 14 = 126
    // effective, splash spread approximates close-range PB3 feel.
    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 14, 9, 6.0, 0, damage_spread: 4);
        shooter.A_PlaySound("weapons/shotgf", CHAN_WEAPON);
    }
}

// ── Sustained-fire hitscan (minigun/MG) ───────────────────────
// PB_Minigun, PB_MG42
class ZetaPB3Minigun : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 2285714;  // ~15/sec
        ZetaWeapon.MinAmmo 1;
        ZetaWeapon.AmmoType "PB_HighCalMag";
        ZetaWeapon.WeaponName "PB3 Minigun";
        Obituary "%k ripped %o apart with a PB3 minigun.";
    }

    override bool IsPickupOf(Weapon other)
    {
        name cls = other.GetClassName();
        return cls == 'PB_Minigun' || cls == 'PB_MG42';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Good mid-to-long, flat curve
        return 1100 / (1 + sqrt(shooter.Distance2D(target) / 3));
    }

    // PB3 source: actors/weapons/Slot5/MINIGUN.dec:527
    //   PB_FireBullets("PB_556x45mmAP", 1, 3, 0, 0, 3)
    // Projectile: zscript/Weapons/Projectiles/BulletDef.HighCal.zsc:13
    //   PB_556x45mmAP.BaseDamage = 25
    // PB3 actual: 25 per round. MG42 variant uses PB_792x57mm (40).
    // Bot fire: 1 × 18 dmg with damage_spread 4 yields 14-22 range,
    // averages mid-20s including the spread which lands close to PB3
    // 25 baseline. ~15/sec FireInterval keeps DPS reasonable.
    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 18, 1, 3.0, 1.5, damage_spread: 4);
        shooter.A_PlaySound("weapons/chngun", CHAN_WEAPON);
    }
}

// ── Precision rifle (DMR, marksman) ───────────────────────────
// PB_DMR
class ZetaPB3DMR : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 5714285;  // ~6/sec
        ZetaWeapon.MinAmmo 1;
        ZetaWeapon.AmmoType "PB_HighCalMag";
        ZetaWeapon.WeaponName "PB3 DMR";
        Obituary "%o was ranged down by %k's DMR.";
    }

    override bool IsPickupOf(Weapon other)
    {
        return other.GetClassName() == 'PB_DMR';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Excellent all-range. Slight preference for long
        double d = shooter.Distance2D(target);
        return 1400 / (1 + sqrt(d / 5));
    }

    // PB3 source: actors/weapons/Slot4/PBRIFLE.dec:848
    //   A_FireProjectile("PB_762x51mmAP", ...)
    // Projectile: zscript/Weapons/Projectiles/BulletDef.HighCal.zsc:39
    //   PB_762x51mmAP.BaseDamage = 165
    // PB3 actual: 165 per shot — highest single-bullet damage in the
    // arsenal (anti-materiel rifle). Bot fire: 1 × 90 dmg keeps the
    // DMR feeling like a precision threat without one-shotting the
    // Pilot. ~6/sec FireInterval limits sustained DPS.
    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 90, 1, 0.6, 0.4, damage_spread: 8);
        shooter.A_PlaySound("weapons/pistol", CHAN_WEAPON);
    }
}

// ── Battle rifle / LMG (flat curve, mid damage) ───────────────
// PB_Carbine, PB_LMG, PB_ChexRifle
class ZetaPB3Carbine : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 3428571;  // ~10/sec
        ZetaWeapon.MinAmmo 1;
        ZetaWeapon.AmmoType "PB_HighCalMag";
        ZetaWeapon.WeaponName "PB3 Carbine";
        Obituary "%o got carbined by %k.";
    }

    override bool IsPickupOf(Weapon other)
    {
        name cls = other.GetClassName();
        return cls == 'PB_Carbine' || cls == 'PB_LMG' || cls == 'PB_ChexRifle';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Steady mid-range utility
        return 1050 / (1 + sqrt(shooter.Distance2D(target) / 3));
    }

    // PB3 source: actors/weapons/Slot4/Carbine.dec:404
    //   PB_FireBullets("PB_556x45mm", 1, 2, 0, 0, 2)
    // Projectile: zscript/Weapons/Projectiles/BulletDef.HighCal.zsc:1
    //   PB_556x45mm.BaseDamage = 22
    // PB3 actual: 22 per round (LMG uses same; ChexRifle similar).
    // Bot fire: 1 × 18 dmg with spread keeps avg near PB3 22 while
    // the ~10/sec rate-of-fire delivers steady mid-range pressure.
    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 18, 1, 2.0, 1.0, damage_spread: 4);
        shooter.A_PlaySound("weapons/pistol", CHAN_WEAPON);
    }
}

// ── Sidearm (pistol, revolver, deagle, mp40, smg) ─────────────
class ZetaPB3Sidearm : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 4000000;
        ZetaWeapon.MinAmmo 1;
        ZetaWeapon.AmmoType "PB_LowCalMag";
        ZetaWeapon.WeaponName "PB3 Sidearm";
        Obituary "%o ate %k's bullet.";
    }

    override bool IsPickupOf(Weapon other)
    {
        name cls = other.GetClassName();
        return cls == 'PB_Pistol'  || cls == 'PB_Revolver' || cls == 'PB_Deagle'
            || cls == 'PB_MP40'    || cls == 'PB_SMG';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Low priority — use when nothing else fits
        return 500 / (1 + sqrt(shooter.Distance2D(target) / 3));
    }

    // PB3 source: mixed projectiles in BulletDef.SmallCal.zsc
    //   PB_Pistol     (PBPISTOL.dec:351)  → PB_45ACPHP    BaseDamage 15
    //   PB_Revolver   (REVOLVER.dec:269)  → PB_500SW      BaseDamage 100
    //   PB_Deagle     (Deagle.dec:284)    → PB_50AE       BaseDamage 105
    //   PB_SMG        (UACSMG.dec:485)    → PB_9x19mmSubs BaseDamage 19
    //   PB_MP40       (MP40.dec:291)      → PB_9x19mm     BaseDamage 17
    // PB3 actual range: 15-105 per shot. Bot fire: single Zeta Fire()
    // can't branch on subclass, so settle at 1 × 28 dmg — splits the
    // difference between hand-cannons (Revolver/Deagle) and pop guns
    // (Pistol/SMG), with damage_spread 6 widening the felt range.
    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 28, 1, 2.5, 1.5, damage_spread: 6);
        shooter.A_PlaySound("weapons/pistol", CHAN_WEAPON);
    }
}

// ── Rocket launcher + grenade launcher (splash) ───────────────
// PB_RocketLauncher, PB_SuperGL
class ZetaPB3RocketLauncher : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 5714285;
        ZetaWeapon.MinAmmo 1;
        ZetaWeapon.AmmoType "PB_RocketAmmo";
        ZetaWeapon.WeaponName "PB3 Rocket Launcher";
        Obituary "%o was turned into paste by %k's rockets.";
    }

    override bool IsPickupOf(Weapon other)
    {
        name cls = other.GetClassName();
        return cls == 'PB_RocketLauncher' || cls == 'PB_SuperGL';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        double d = shooter.Distance3D(target);
        // Splash suicide guard — NEGATIVE rating close-in
        if (d < 160) return -100;
        return 2100 / (1 + sqrt(shooter.Distance2D(target) * 1.4));
    }

    // PB3 source: actors/weapons/EXPLOSIVES.dec:99
    //   Actor PB_Rocket { Speed 45 / Damage (160) / DamageType Explosive }
    // PB3 actual: 160 direct hit + splash. Spawning PB_Rocket directly
    // lets the bot inherit PB3's projectile (damage + radius + decals)
    // rather than vanilla Rocket (20). Fallback: if PB3 isn't loaded
    // the spawn fails and the bot wastes its FireInterval, which is
    // acceptable for a copilot-mod that requires PB3 to begin with.
    override void Fire(Actor shooter, Actor target)
    {
        double pitch = 0;
        if (target != null && target.Distance2D(shooter) > 0)
            pitch = ((target.pos.z - shooter.pos.z) * 25 / target.Distance2D(shooter));
        shooter.SpawnMissileAngle("PB_Rocket", shooter.angle, pitch);
    }
}

// ── Flamethrower / cryo (close-range sustained area) ──────────
// PB_Flamethrower, PB_CryoRifle
class ZetaPB3Flamer : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 1428571;
        ZetaWeapon.MinAmmo 1;
        ZetaWeapon.AmmoType "PB_Fuel";
        ZetaWeapon.WeaponName "PB3 Flamer";
        Obituary "%o was cooked by %k's flamer.";
    }

    override bool IsPickupOf(Weapon other)
    {
        name cls = other.GetClassName();
        return cls == 'PB_Flamethrower' || cls == 'PB_CryoRifle';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        double d = shooter.Distance2D(target);
        if (d > 384) return 50;  // falls off fast past flame range
        return 900 / (1 + sqrt(d / 2));
    }

    // PB3 source: zscript/Weapons/FlamerStuff.zsc:7
    //   Flame particle class { Damage 5; DamageType "Fire"; }
    // PB3 actual: 5 dmg per flame particle, very fast emission rate.
    // PB3 hits ~10+ particles per second on a sustained beam, giving
    // 50+ DPS at close range. Bot fire: synthetic hitscan can't model
    // a real flame cone, so 3 bullets × 6 dmg = 18 effective per Fire()
    // at ~7/sec FireInterval = ~126 DPS — slightly above PB3's flame
    // stream to compensate for the wider spread missing hits.
    override void Fire(Actor shooter, Actor target)
    {
        // Synthetic flame-like hitscan — multiple weak bullets, wide spread
        ZetaBullet.FireBullets(shooter, "Red", target, 6, 3, 8.0, 4.0, damage_spread: 2);
        shooter.A_PlaySound("weapons/plasmaf", CHAN_WEAPON);
    }
}

// ── Plasma / pulse (all-range energy) ─────────────────────────
// PB_M1Plasma, PB_M2Plasma, PB_PulseCannon, PB_DualPulseCannon, PB_Demontech, PB_Nailgun
class ZetaPB3Plasma : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 2285714;
        ZetaWeapon.MinAmmo 1;
        ZetaWeapon.AmmoType "PB_Cell";
        ZetaWeapon.WeaponName "PB3 Plasma";
        Obituary "%o was vaporized by %k's plasma.";
    }

    override bool IsPickupOf(Weapon other)
    {
        name cls = other.GetClassName();
        return cls == 'PB_M1Plasma'      || cls == 'PB_M2Plasma'
            || cls == 'PB_PulseCannon'   || cls == 'PB_DualPulseCannon'
            || cls == 'PB_Demontech'     || cls == 'PB_Nailgun';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Great everywhere but melee range
        double d = shooter.Distance2D(target);
        if (d < 96) return 300;
        return 1300 / (1 + sqrt(d / 4));
    }

    // PB3 source: zscript/Weapons/Slot7/PlasmaM1.zs:227 (FireProjectile)
    //   Class Plasma_Ball : PB_ProjectileAlt { Damage 8; Speed 60; }
    // PB3 actual: 8 dmg per ball but high rate-of-fire (~14/sec) yields
    // sustained ~112 DPS. Spawning Plasma_Ball directly gives the bot
    // PB3's exact projectile (faster, brighter, correct damage type)
    // instead of vanilla PlasmaBall (5 dmg, slower). FireInterval is
    // ~7/sec for bots, so DPS is half player rate — fair trade.
    override void Fire(Actor shooter, Actor target)
    {
        double pitch = 0;
        if (target != null && target.Distance2D(shooter) > 0)
            pitch = ((target.pos.z - shooter.pos.z) * 25 / target.Distance2D(shooter));
        shooter.SpawnMissileAngle("Plasma_Ball", shooter.angle, pitch);
    }
}

// ── Room-clear superweapon (BFG, railgun, unmaker) ────────────
class ZetaPB3BFG : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 11428571;
        ZetaWeapon.MinAmmo 40;
        ZetaWeapon.AmmoUse 40;
        ZetaWeapon.AmmoType "PB_Cell";
        ZetaWeapon.WeaponName "PB3 BFG";
        Obituary "%o was erased by %k's BFG.";
    }

    override bool IsPickupOf(Weapon other)
    {
        name cls = other.GetClassName();
        return cls == 'PB_BFG9000' || cls == 'PB_Railgun' || cls == 'PB_Unmaker';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Only worth the ammo when something serious is on the field
        if (target.SpawnHealth() < 200) return 100;  // don't waste on grunts
        return 4500 / (1 + shooter.Distance2D(target) * 3);
    }

    // PB3 source: actors/weapons/Slot9/BFGMKIV.dec:1085
    //   Actor SuperBFGBall { Speed 24 / Damage 500 / DamageType Disintegrate }
    // PB3 actual: 500 direct + heavy radius from BFG tracer beams.
    // Vanilla BFGBall is 100*random(1,8) = 100-800 with tracer effect.
    // SuperBFGBall is PB3's seeker-missile variant fired by PB_BFG9000.
    // Bot fire: spawn SuperBFGBall — same projectile the player fires,
    // 40-ammo MinAmmo gate + ~9sec FireInterval rate-limits it heavily.
    override void Fire(Actor shooter, Actor target)
    {
        double pitch = 0;
        if (target != null && target.Distance2D(shooter) > 0)
            pitch = ((target.pos.z - shooter.pos.z) * 25 / target.Distance2D(shooter));
        shooter.SpawnMissileAngle("SuperBFGBall", shooter.angle, pitch);
    }
}

// ── Melee (chainsaw, axe) ─────────────────────────────────────
class ZetaPB3Chainsaw : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 2000000;
        ZetaWeapon.AmmoUse 0;
        ZetaWeapon.WeaponName "PB3 Chainsaw";
        Obituary "%o was dismembered by %k's chainsaw.";
    }

    override bool IsPickupOf(Weapon other)
    {
        name cls = other.GetClassName();
        return cls == 'PB_Chainsaw' || cls == 'PB_Axe';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Only in melee range
        if (shooter.Distance2D(target) > 80) return -50;
        return shooter.Health * 3;  // high priority when up close and healthy
    }

    // PB3 source: actors/weapons/Slot1/SAW.dec:1257
    //   Actor SawSwing : FastProjectile { Damage 10; Speed 50; }
    //   Actor SawNoPush : SawSwing { Damage 14; } (no-knockback variant)
    // PB3 actual: 10-14 per saw tick but rips/penetrates so a sustained
    // contact lands many hits/sec. Axe (Slot1/Axe.dec:439) is 120 per
    // swing. Bot fire: LineAttack 12 × Random(1,3) = 12-36 per Fire()
    // matches a "good chainsaw rip" while ~0.06sec FireInterval makes
    // sustained contact lethal as in PB3.
    override void Fire(Actor shooter, Actor target)
    {
        shooter.LineAttack(shooter.angle, 80, 0, 12 * Random(1, 3), "Melee", "BulletPuff", 0);
    }

    override bool IsMelee() { return true; }
}

// ── Fists (last-resort melee) ─────────────────────────────────
class ZetaPB3Fists : ZetaWeapon
{
    default
    {
        ZetaWeapon.FireInterval 5142857;
        ZetaWeapon.AmmoUse 0;
        ZetaWeapon.WeaponName "PB3 Fists";
        Obituary "%k punched %o.";
    }

    override bool IsPickupOf(Weapon other)
    {
        return other.GetClassName() == 'PB_Fists';
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Last resort — only when nothing else works
        if (shooter.Distance2D(target) > 48) return -50;
        if (shooter.CheckInventory("PowerStrength", 1))
            return shooter.Health * 5;
        return -30;
    }

    // PB3 source: actors/weapons/Slot1/MELEE.dec
    //   MeleeStrike1: Damage (random(13,18)) — normal punch  (line 1726)
    //   MeleeStrike2Smash: Damage 32 — berserk-fueled smash (line 1761)
    // PB3 actual: 13-18 normal, 32 berserk-smash per punch. Bot fire:
    // LineAttack with discrete damage matches PB3's range. Berserk
    // (PowerStrength) bumps to 12 × Random(1,4) = 12-48 to bracket
    // the PB3 32 baseline; normal 4 × Random(1,4) = 4-16 trims slightly
    // below 15 since bots use fists as a last resort anyway.
    override void Fire(Actor shooter, Actor target)
    {
        int dmg = (shooter.CheckInventory("PowerStrength", 1) ? 12 : 4) * Random(1, 4);
        shooter.LineAttack(shooter.angle, 48, 0, dmg, "Melee", "BulletPuff", 0);
    }

    override bool IsMelee() { return true; }
}
