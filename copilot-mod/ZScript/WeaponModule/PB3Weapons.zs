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
// for projectiles — same pattern as vanilla ZetaDoomWeapons. Bot
// damage is approximate; the point is correct range/target behavior.

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
        string cls = other.GetClass();
        return cls == "PB_Shotgun" || cls == "PB_Autoshotgun"
            || cls == "PB_SSG"     || cls == "PB_QuadSG";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Peak at close-mid (128-512u), fall off beyond
        double d = shooter.Distance2D(target);
        if (d < 64) return 500;   // still decent point-blank
        return 1200 / (1 + sqrt(d / 2));
    }

    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 12, 8, 6.0, 0, damage_spread: 4);
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
        string cls = other.GetClass();
        return cls == "PB_Minigun" || cls == "PB_MG42";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Good mid-to-long, flat curve
        return 1100 / (1 + sqrt(shooter.Distance2D(target) / 3));
    }

    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 8, 1, 3.0, 1.5);
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
        return other.GetClass() == "PB_DMR";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Excellent all-range. Slight preference for long
        double d = shooter.Distance2D(target);
        return 1400 / (1 + sqrt(d / 5));
    }

    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 25, 1, 0.6, 0.4, damage_spread: 3);
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
        string cls = other.GetClass();
        return cls == "PB_Carbine" || cls == "PB_LMG" || cls == "PB_ChexRifle";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Steady mid-range utility
        return 1050 / (1 + sqrt(shooter.Distance2D(target) / 3));
    }

    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 10, 1, 2.0, 1.0);
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
        string cls = other.GetClass();
        return cls == "PB_Pistol"  || cls == "PB_Revolver" || cls == "PB_Deagle"
            || cls == "PB_MP40"    || cls == "PB_SMG";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Low priority — use when nothing else fits
        return 500 / (1 + sqrt(shooter.Distance2D(target) / 3));
    }

    override void Fire(Actor shooter, Actor target)
    {
        ZetaBullet.FireBullets(shooter, "Gold", target, 6, 1, 2.5, 1.5);
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
        string cls = other.GetClass();
        return cls == "PB_RocketLauncher" || cls == "PB_SuperGL";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        double d = shooter.Distance3D(target);
        // Splash suicide guard — NEGATIVE rating close-in
        if (d < 160) return -100;
        return 2100 / (1 + sqrt(shooter.Distance2D(target) * 1.4));
    }

    override void Fire(Actor shooter, Actor target)
    {
        double pitch = 0;
        if (target != null && target.Distance2D(shooter) > 0)
            pitch = ((target.pos.z - shooter.pos.z) * 25 / target.Distance2D(shooter));
        shooter.SpawnMissileAngle("Rocket", shooter.angle, pitch);
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
        string cls = other.GetClass();
        return cls == "PB_Flamethrower" || cls == "PB_CryoRifle";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        double d = shooter.Distance2D(target);
        if (d > 384) return 50;  // falls off fast past flame range
        return 900 / (1 + sqrt(d / 2));
    }

    override void Fire(Actor shooter, Actor target)
    {
        // Synthetic flame-like hitscan — multiple weak bullets, wide spread
        ZetaBullet.FireBullets(shooter, "Red", target, 4, 3, 8.0, 4.0);
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
        string cls = other.GetClass();
        return cls == "PB_M1Plasma"      || cls == "PB_M2Plasma"
            || cls == "PB_PulseCannon"   || cls == "PB_DualPulseCannon"
            || cls == "PB_Demontech"     || cls == "PB_Nailgun";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Great everywhere but melee range
        double d = shooter.Distance2D(target);
        if (d < 96) return 300;
        return 1300 / (1 + sqrt(d / 4));
    }

    override void Fire(Actor shooter, Actor target)
    {
        double pitch = 0;
        if (target != null && target.Distance2D(shooter) > 0)
            pitch = ((target.pos.z - shooter.pos.z) * 25 / target.Distance2D(shooter));
        shooter.SpawnMissileAngle("PlasmaBall", shooter.angle, pitch);
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
        string cls = other.GetClass();
        return cls == "PB_BFG9000" || cls == "PB_Railgun" || cls == "PB_Unmaker";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Only worth the ammo when something serious is on the field
        if (target.SpawnHealth() < 200) return 100;  // don't waste on grunts
        return 4500 / (1 + shooter.Distance2D(target) * 3);
    }

    override void Fire(Actor shooter, Actor target)
    {
        double pitch = 0;
        if (target != null && target.Distance2D(shooter) > 0)
            pitch = ((target.pos.z - shooter.pos.z) * 25 / target.Distance2D(shooter));
        shooter.SpawnMissileAngle("BFGBall", shooter.angle, pitch);
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
        string cls = other.GetClass();
        return cls == "PB_Chainsaw" || cls == "PB_Axe";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Only in melee range
        if (shooter.Distance2D(target) > 80) return -50;
        return shooter.Health * 3;  // high priority when up close and healthy
    }

    override void Fire(Actor shooter, Actor target)
    {
        shooter.LineAttack(shooter.angle, 80, 0, 15 * Random(1, 4), "Melee", "BulletPuff", 0);
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
        return other.GetClass() == "PB_Fists";
    }

    override double RateSelf(Actor shooter, Actor target)
    {
        // Last resort — only when nothing else works
        if (shooter.Distance2D(target) > 48) return -50;
        if (shooter.CheckInventory("PowerStrength", 1))
            return shooter.Health * 5;
        return -30;
    }

    override void Fire(Actor shooter, Actor target)
    {
        int dmg = (shooter.CheckInventory("PowerStrength", 1) ? 20 : 2) * Random(1, 10);
        shooter.LineAttack(shooter.angle, 48, 0, dmg, "Melee", "BulletPuff", 0);
    }

    override bool IsMelee() { return true; }
}
