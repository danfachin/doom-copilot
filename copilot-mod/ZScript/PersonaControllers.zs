// Four persona controllers. Each overrides the virtual hooks from
// DoomCopilotController with the persona's numeric profile.
//
// Tuning notes:
//   Numbers below are hand-tuned starting points from the Item 4
//   scope. Item 8 (calibration) will generate empirically-tuned
//   replacements from Dan's telemetry — these are the seed values.
//
// Item 9 adds loadouts (2 primary + 1 sidearm, infinite-ammo sidearm)
// and movement-feel knobs (MoveSpeedMult, StrafeDamping). Default
// personas dial speed to ~0.7 and strafe to ~0.4 for Warhammer-walk
// feel; Death-Wish stays near ZetaBot defaults.

// ── Sharpshooter ──────────────────────────────────────────────
// Ranged overwatch. Hangs back, shoots precisely, preserves self.
class DC_SharpshooterController : DoomCopilotController
{
    override string PersonaName()      { return "Sharpshooter"; }

    // Hangs back — start following only when Dan is well ahead.
    override double FollowMin()        { return 400.0; }
    override double FollowMax()        { return 250.0; }

    // Preserves self aggressively (35% HP retreat).
    override double FleeHpFrac()       { return 0.35; }
    override double FleeEnemyDist()    { return 1280.0; }
    override bool   CanFlee()          { return true; }

    // Tight aim, fast target lock.
    override double AimScatterMult()   { return 0.3; }
    override double TurnSpeedMult()    { return 1.4; }

    // Marksman standoff: plant between ~640 and ~1024. Well outside
    // the Pilot's SSG / shotgun cone, inside the DMR's sweet spot.
    override double EngagementCloseRange()   { return 1024.0; }
    override double EngagementBackoffRange() { return  640.0; }

    // Slow and grounded — marksmen don't juke. Cut further from 0.65/0.3
    // after 2026-04-20 playtest showed the squad zipping across the
    // Pilot's firing arcs and getting clipped by friendly fire.
    override double MoveSpeedMult()    { return 0.50; }
    override double StrafeDamping()    { return 0.15; }

    // DMR + pump shotgun (effectively slug-role at mid range) + revolver.
    override string PrimaryClass1()    { return "PB_DMR"; }
    override string PrimaryClass2()    { return "PB_Shotgun"; }
    override string SidearmClass()     { return "PB_Revolver"; }
    override string SidearmAmmoClass() { return "PB_LowCalMag"; }
}

// ── Brawler ───────────────────────────────────────────────────
// Close-range aggressor. In the thick of it, rarely retreats.
class DC_BrawlerController : DoomCopilotController
{
    override string PersonaName()      { return "Brawler"; }

    // Stays close to Dan; quick to re-close.
    override double FollowMin()        { return 150.0; }
    override double FollowMax()        { return 100.0; }

    // Low HP threshold — aggressive hold.
    override double FleeHpFrac()       { return 0.15; }
    override double FleeEnemyDist()    { return 768.0; }
    override bool   CanFlee()          { return true; }

    // Less precise but keeps up — closer range = less skill needed.
    override double AimScatterMult()   { return 0.9; }
    override double TurnSpeedMult()    { return 1.2; }

    // Closes aggressively for flamer/SSG range. Plants between 96-192.
    override double EngagementCloseRange()   { return 192.0; }
    override double EngagementBackoffRange() { return  96.0; }

    // Moderate speed, mid damping — advances purposefully, minor weave.
    // Trimmed from 0.85/0.5 after 2026-04-20 playtest.
    override double MoveSpeedMult()    { return 0.65; }
    override double StrafeDamping()    { return 0.30; }

    // Flamer (primary close-in) + SSG (secondary burst) + fire axe.
    override string PrimaryClass1()    { return "PB_Flamethrower"; }
    override string PrimaryClass2()    { return "PB_SSG"; }
    override string SidearmClass()     { return "PB_Axe"; }
    override string SidearmAmmoClass() { return ""; }
}

// ── Tank ──────────────────────────────────────────────────────
// Body-blocks near the player. High survivability, moderate damage.
class DC_TankController : DoomCopilotController
{
    override string PersonaName()      { return "Tank"; }

    // Very tight formation — stays right next to Dan.
    override double FollowMin()        { return 180.0; }
    override double FollowMax()        { return 120.0; }

    // Survives to maintain formation — flees at 50% HP.
    override double FleeHpFrac()       { return 0.50; }
    override double FleeEnemyDist()    { return 1024.0; }
    override bool   CanFlee()          { return true; }

    // Medium aim, moderate turn (holds ground).
    override double AimScatterMult()   { return 0.8; }
    override double TurnSpeedMult()    { return 1.0; }

    // Midfield anchor: 320-512u. Keeps minigun/rocket useful without
    // eating the Pilot's point-blank shots. Rockets self-guard via
    // the <160u RateSelf penalty so they won't splash the Tank itself.
    override double EngagementCloseRange()   { return 512.0; }
    override double EngagementBackoffRange() { return 320.0; }

    // Heaviest, slowest, least strafe — owns the ground.
    // Trimmed from 0.6/0.25 after 2026-04-20 playtest.
    override double MoveSpeedMult()    { return 0.45; }
    override double StrafeDamping()    { return 0.12; }

    // Minigun + rocket launcher + SMG sidearm.
    override string PrimaryClass1()    { return "PB_Minigun"; }
    override string PrimaryClass2()    { return "PB_RocketLauncher"; }
    override string SidearmClass()     { return "PB_SMG"; }
    override string SidearmAmmoClass() { return "PB_LowCalMag"; }
}

// ── Death-Wish ────────────────────────────────────────────────
// Never flees. Always advances. Chaplain-rush energy.
class DC_DeathwishController : DoomCopilotController
{
    override string PersonaName()      { return "Death-Wish"; }

    // Ignores Dan entirely — always charging forward.
    override double FollowMin()        { return 2000.0; } // effectively never
    override double FollowMax()        { return 1800.0; }

    // Never flees.
    override bool   CanFlee()          { return false; }
    // (HpFrac/EnemyDist irrelevant when CanFlee is false but safe defaults.)
    override double FleeHpFrac()       { return 0.0; }
    override double FleeEnemyDist()    { return 0.0; }

    // Spray-and-pray precision, maximum turn speed.
    override double AimScatterMult()   { return 1.8; }
    override double TurnSpeedMult()    { return 1.8; }

    // Always closing. Tiny standoff so they keep rushing monsters but
    // still have a bare-minimum back-off at point-blank so they don't
    // rocket-splash themselves.
    override double EngagementCloseRange()   { return 128.0; }
    override double EngagementBackoffRange() {  return 64.0; }

    // Full speed, near-full twitch — the chaos variable.
    // Slight trim from 1.0/0.8 so even Death-Wish reads as "berserk"
    // rather than "bunny-hopping" after the 2026-04-20 tuning pass.
    override double MoveSpeedMult()    { return 0.90; }
    override double StrafeDamping()    { return 0.70; }

    // Plasma rifle + rocket launcher + chainsaw sidearm.
    override string PrimaryClass1()    { return "PB_M1Plasma"; }
    override string PrimaryClass2()    { return "PB_RocketLauncher"; }
    override string SidearmClass()     { return "PB_Chainsaw"; }
    override string SidearmAmmoClass() { return ""; }
}
