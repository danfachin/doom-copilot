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

    // Calibration pass (CHAT-CC-260519-054, 49 sessions / 44 deaths /
    // 707 min): Dan's p50 survival low-water is 76 HP; p25 is 52. The
    // earlier 0.35 seed bailed far below Dan's actual retreat instinct.
    // 0.64 = midpoint of the safe (0.76) and tank (0.52) thresholds.
    override double FleeHpFrac()       { return 0.64; }
    override double FleeEnemyDist()    { return 1280.0; }
    override bool   CanFlee()          { return true; }

    // Tight aim, fast target lock.
    override double AimScatterMult()   { return 0.3; }
    override double TurnSpeedMult()    { return 1.4; }

    // Calibrated standoff: DMR kills land at p25=172, median=232,
    // p75=422 in Dan's telemetry — way inside the prior 640-1024 band.
    // New envelope brackets the DMR sweet spot (300-600) so the bot
    // plants where shots actually convert.
    override double EngagementCloseRange()   { return 600.0; }
    override double EngagementBackoffRange() { return 300.0; }

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
// Close-range kiter. Dashes in, dashes out — constant motion oscillation.
// The engagement envelope swings every ~0.8s so the bot alternately
// commits to point-blank then backpedals to range. Fires throughout.
class DC_BrawlerController : DoomCopilotController
{
    override string PersonaName()      { return "Brawler"; }

    // Stays close to Dan; quick to re-close.
    override double FollowMin()        { return 150.0; }
    override double FollowMax()        { return 100.0; }

    // Calibration pass: Dan's p10 survival floor is 31. Seed 0.15 was
    // brave but below the empirical floor — small nudge to 0.20 keeps
    // the aggressive identity while respecting the data.
    override double FleeHpFrac()       { return 0.20; }
    override double FleeEnemyDist()    { return 768.0; }
    override bool   CanFlee()          { return true; }

    // Less precise but keeps up — closer range = less skill needed.
    override double AimScatterMult()   { return 0.9; }
    override double TurnSpeedMult()    { return 1.2; }

    // Kite oscillation. Subroutine_Attack consults these every tic
    // (zetabot-fork/zscript.zs:2549/2557): if distance > Close → advance,
    // if distance < Backoff → back off, otherwise plant and shoot. By
    // returning time-varying values we make the bot continuously chase
    // a moving target band — a dash-in / dash-out kite without touching
    // the attack loop itself.
    //
    //   Phase 0 (dash-in,  ~0.8s): band = 60-120u, bot sprints close
    //   Phase 1 (dash-out, ~0.8s): band = 500-600u, bot backpedals
    //
    // Empirical Brawler-weapon ranges from telemetry (Flamethrower
    // median 415, SSG median 314) emerge as the time-average between
    // the two phases — bot fires both directions of the kite cycle.
    const KITE_PHASE_TICS = 28;

    // Last phase observed by KitePhase(). Default 0 — first transition
    // out of phase 0 will emit; the implicit phase-0-on-spawn is
    // undocumented in logs but that's fine for tracing.
    int lastKitePhase;

    int KitePhase()
    {
        int phase = (level.time / KITE_PHASE_TICS) & 1;
        if (phase != lastKitePhase)
        {
            // Diagnostic emit gated on dc_debug_brawler_kite (separate
            // from the global dc_debug spam — lets us scope the trace
            // to just the kite without re-enabling everything else).
            let cv = CVar.FindCVar("dc_debug_brawler_kite");
            if (cv && cv.GetBool() && possessed)
            {
                string enemyName = "none";
                double enemyDist = -1;
                if (enemy)
                {
                    enemyName = enemy.GetClassName();
                    enemyDist = possessed.Distance3D(enemy);
                }
                console.printf("[DC]{\"t\":\"kite_phase\",\"tic\":%d,"
                    .."\"persona\":\"%s\",\"phase\":%d,"
                    .."\"close\":%.0f,\"backoff\":%.0f,"
                    .."\"enemy\":\"%s\",\"dist_enemy\":%.0f}",
                    level.time, PersonaName(), phase,
                    phase == 0 ? 120.0 : 600.0,
                    phase == 0 ?  60.0 : 500.0,
                    enemyName, enemyDist);
            }
            lastKitePhase = phase;
        }
        return phase;
    }

    override double EngagementCloseRange()   { return KitePhase() == 0 ? 120.0 : 600.0; }
    override double EngagementBackoffRange() { return KitePhase() == 0 ?  60.0 : 500.0; }

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

    // Calibration pass: Dan's p50 survival low-water is 76 HP. The
    // Tank's whole identity is "owns the ground until it can't" — match
    // the Pilot's actual retreat reflex rather than under-retreating
    // at 50%.
    override double FleeHpFrac()       { return 0.76; }
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

    // Minigun + rocket launcher + Deagle sidearm. Calibration showed
    // Dan dwells on the Deagle (127s) 5.7x more than the SMG (22s), so
    // the Tank inherits the hand-cannon. The Deagle still routes through
    // the PB3Sidearm ZetaWeapon wrapper (same PB_LowCalMag virtual ammo)
    // since the wrapper's IsPickupOf accepts Pistol/Revolver/Deagle/SMG/MP40
    // uniformly — see copilot-mod/ZScript/WeaponModule/PB3Weapons.zs:211.
    override string PrimaryClass1()    { return "PB_Minigun"; }
    override string PrimaryClass2()    { return "PB_RocketLauncher"; }
    override string SidearmClass()     { return "PB_Deagle"; }
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
