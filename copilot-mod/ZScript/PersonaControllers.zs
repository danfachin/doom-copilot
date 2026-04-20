// Four persona controllers. Each overrides the virtual hooks from
// DoomCopilotController with the persona's numeric profile.
//
// Tuning notes:
//   Numbers below are hand-tuned starting points from the Item 4
//   scope. Item 8 (calibration) will generate empirically-tuned
//   replacements from Dan's telemetry — these are the seed values.

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
}
