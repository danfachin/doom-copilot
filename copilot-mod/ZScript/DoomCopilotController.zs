// DoomCopilotController — base persona-aware controller.
//
// Exposes virtual hooks that persona subclasses override to produce
// distinct bot behaviors without duplicating ZetaBot's core logic.
// The dials here are the minimum viable set for Item 4:
//   - Follow distance thresholds (start/stop following the player)
//   - Flee HP fraction (retreat threshold, or never)
//   - Flee enemy distance
//   - Aim scatter multiplier (sharpshooter=tight, deathwish=loose)
//   - Turn speed multiplier
//   - Can-flee flag (death-wish = false)
//
// More dials (RateSelf weapon bias, target priority scale) come
// online in Item 7 alongside the PB3 weapon module.
//
// Item 9 additions:
//   - Loadout hooks (PrimaryClass1/2, SidearmClass, SidearmAmmoClass)
//   - Movement tuning (MoveSpeedMult, StrafeDamping) — Warhammer-walk
//     feel. Death-Wish keeps faster / twitchier movement.
//
// Override pattern: we subclass key ZTBotController methods. ZetaBot's
// methods are not declared `virtual` in all cases, so where ZScript
// allows override by matching signature we do; where not, we duplicate
// the method body with persona-aware tweaks. Current overrides:
//   - ShouldFollow (uses FollowMin/FollowMax)
//   - Subroutine_Flee (uses FleeHpFrac, FleeEnemyDist, CanFlee)
//   - RefreshSkills (applies AimScatterMult, TurnSpeedMult to CVars)
//   - RandomStrafe (applies StrafeDamping)

class DoomCopilotController : ZTBotController
{
    // ── Persona identity ───────────────────────────────────────

    virtual string PersonaName()       { return "Generic"; }

    // ── Telemetry state ────────────────────────────────────────
    //
    // spawnTic is set once in GiveLoadout (which runs right after the
    // possessed pawn is confirmed live). DC_DebugHandler uses it to
    // compute tic_alive on death.
    int spawnTic;

    // ── Follow behavior ────────────────────────────────────────

    // Start following if distance to commander exceeds this.
    virtual double FollowMin()         { return 300.0; }
    // Stop following if distance to commander is below this.
    virtual double FollowMax()         { return 60.0; }

    // ── Flee behavior ──────────────────────────────────────────

    // Retreat when HP drops below (maxHP * fraction). 0 disables flee.
    virtual double FleeHpFrac()        { return 1.0 / 7.0; }
    // Only flee if an enemy is within this distance.
    virtual double FleeEnemyDist()     { return 1024.0; }
    // Global flee disable (death-wish never retreats).
    virtual bool   CanFlee()           { return true; }

    // ── Combat tuning ──────────────────────────────────────────

    // Multiplier on zb_aimstutter (CVar). 0.3 = sharpshooter,
    // 1.5 = spray-and-pray. 1.0 preserves ZetaBot default.
    virtual double AimScatterMult()    { return 1.0; }
    // Multiplier on zb_turnspeed (CVar). Higher = faster target lock.
    virtual double TurnSpeedMult()     { return 1.0; }

    // Engagement envelope — the per-persona replacement for ZetaBot's
    // hardcoded 128-256u window. Sharpshooter holds at DMR range,
    // Brawler closes to point-blank, Tank plants at midfield. Bots
    // advance while beyond Close, backpedal inside Backoff, plant
    // and shoot in between. Keep Close > Backoff + pawn radius or
    // the bot oscillates between the two bands.
    override double EngagementCloseRange()   { return 256.0; }
    override double EngagementBackoffRange() { return 128.0; }

    // ── Movement feel (Item 9) ─────────────────────────────────

    // Multiplier on the possessed pawn's default Speed. <1.0 = slower,
    // deliberate movement ("walking-tank" Warhammer feel). Applied
    // once in PostPossess. Death-Wish keeps 1.0.
    virtual double MoveSpeedMult()     { return 0.75; }

    // Probability (0..1) that any given RandomStrafe tick actually
    // applies a side-move, and scalar on the momentum-drift noise.
    // Lower = more grounded/owns-the-ground, higher = twitchier.
    // 1.0 reproduces ZetaBot's default. Death-Wish ~0.8.
    virtual double StrafeDamping()     { return 0.4; }

    // ── Loadout (Item 9) ───────────────────────────────────────
    //
    // Weapon class names given to the possessed pawn on spawn.
    // Blank ("") means "skip this slot" — we hand what the persona
    // carries, the bot does not pick up anything it stumbles over.
    //
    // SidearmAmmoClass feeds the infinite-ammo top-up at spawn
    // (blank = melee/no ammo). The sidearm's RateSelf keeps it at
    // the bottom of the picking order; it only fires when primaries
    // are dry or out-of-range.

    virtual string PrimaryClass1()     { return ""; }
    virtual string PrimaryClass2()     { return ""; }
    virtual string SidearmClass()      { return ""; }
    virtual string SidearmAmmoClass()  { return ""; }

    // ── Overrides ──────────────────────────────────────────────

    // Persona-aware follow thresholds. Replaces ZTBotController.ShouldFollow.
    override bool ShouldFollow(Actor who)
    {
        if (!who) return false;

        double d = possessed.Distance3D(who);
        if (d > FollowMin()) return true;
        if (d < FollowMax()) return false;
        return !possessed.CheckSight(who);
    }

    // Persona-aware flee logic. Death-wish returns immediately to wander.
    override void Subroutine_Flee()
    {
        if (!CanFlee())
        {
            ConsiderSetBotState(BS_WANDERING);
            return;
        }

        if (DodgeAndUse())
        {
            if (currNode)
                navDest = currNode.RandomNeighborRoughlyToward(vel.xy, 0.5);
            else
                navDest = null;

            ConsiderSetBotState(BS_WANDERING);
        }

        double hpThresh = double(possessed.default.Health) * FleeHpFrac();
        if (enemy &&
            possessed.Distance3D(enemy) < FleeEnemyDist() &&
            possessed.CheckSight(enemy) &&
            double(possessed.Health) < hpThresh)
        {
            MoveAwayFrom(enemy);
        }
        else
        {
            ConsiderSetBotState(BS_WANDERING);
        }
    }

    // Persona-aware skill refresh. Multiplies CVar values by persona factors.
    override void RefreshSkills()
    {
        imprecision = CVar.GetCVar("zb_aimstutter").GetFloat() * AimScatterMult();
        maxAngleRate = CVar.GetCVar('zb_turnspeed').GetFloat() * TurnSpeedMult();
    }

    // Persona-aware strafing. Damps the momentum drift and gates the
    // actual side-move on a probability roll — gives the bot time to
    // plant and shoot instead of juking every tic. Death-Wish passes
    // through at near-full-twitch via a ~0.8 StrafeDamping.
    override void RandomStrafe()
    {
        double d = StrafeDamping();

        // Let momentum decay back toward zero so damped personas don't
        // pin at ±1 after a few random ticks.
        strafeMomentum *= (1.0 - (1.0 - d) * 0.15);
        strafeMomentum += FRandom(-0.1, 0.1) * d;

        if (strafeMomentum < -1) strafeMomentum = -1;
        if (strafeMomentum > 1)  strafeMomentum =  1;

        // Gate the actual side-move. At d=0.4 the bot skips ~60% of
        // strafe opportunities, which reads as "owns the ground."
        if (FRandom(0.0, 1.0) > d) return;

        if (strafeMomentum > 0) possessed.MoveRight();
        else                     possessed.MoveLeft();
    }

    // Prefer the Pilot over squadmates as commander. Vanilla
    // PickCommander picks randomly from VisibleFriends — with three
    // bots spawning on top of each other, they see each other first
    // and commander each other in a ring. Telemetry showed dist_cmd
    // pinned at 136 (squadmate distance) instead of growing with the
    // Pilot's movement (session_20260420_214156.log). Fix: walk the
    // player list, attach to the first live console player in sight;
    // fall back to Super only if the Pilot is unreachable.
    override void PickCommander()
    {
        if (commander != null) return;
        if (possessed == null) { Super.PickCommander(); return; }

        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!playeringame[i]) continue;
            let pmo = players[i].mo;
            if (!pmo || pmo.health <= 0) continue;
            if (Actor(pmo) == Actor(possessed)) continue;   // don't self-commander if our pawn has a player slot

            if (SetCommander(pmo))
            {
                BotChat("COMM", 0.8);
                return;
            }
        }

        Super.PickCommander();
    }

    // Flee trigger. ZetaBot never auto-transitions into BS_FLEEING on
    // low HP — our Subroutine_Flee override only matters once the state
    // is already fleeing. So on every pain event we check the persona's
    // flee threshold and kick the state over. Also routes through the
    // same HP gating as Subroutine_Flee (enemy in sight, within range)
    // so bots don't flip-flee from a single pop-shot from off-map.
    override void PlayPain()
    {
        Super.PlayPain();

        if (!CanFlee()) return;
        if (bstate == BS_FLEEING) return;
        if (possessed == null) return;

        double hpThresh = double(possessed.default.Health) * FleeHpFrac();
        if (double(possessed.Health) >= hpThresh) return;

        // Only flee from something we can actually see — don't bail
        // from hitscan that came through a wall.
        if (!enemy || !possessed.CheckSight(enemy)) return;
        if (possessed.Distance3D(enemy) > FleeEnemyDist()) return;

        ConsiderSetBotState(BS_FLEEING);
    }

    // Log state transitions at dc_debug >= 1. Only fires on real
    // changes (s != bstate), matching where ZetaBot would DebugLog.
    override void SetBotState(uint s)
    {
        if (s != bstate && DC_DebugHandler.DebugLevel() >= 1 && possessed)
        {
            string enemyName = "none";
            double enemyDist = -1;
            if (enemy)
            {
                enemyName = enemy.GetClassName();
                enemyDist = possessed.Distance3D(enemy);
            }
            double cmdDist = commander ? possessed.Distance3D(commander) : -1;

            console.printf("[DC]{\"t\":\"state_change\",\"tic\":%d,"
                .."\"persona\":\"%s\",\"from\":\"%s\",\"to\":\"%s\","
                .."\"hp\":%d,\"dist_cmd\":%.0f,"
                .."\"enemy\":\"%s\",\"dist_enemy\":%.0f}",
                level.time, PersonaName(),
                BStateNames[bstate], BStateNames[s],
                possessed.health, cmdDist, enemyName, enemyDist);
        }
        Super.SetBotState(s);
    }

    // Called from DC_DebugHandler.WorldTick at 2 Hz when dc_debug >= 2.
    void EmitTickLog()
    {
        if (!possessed) return;
        string enemyName = "none";
        double enemyDist = -1;
        if (enemy)
        {
            enemyName = enemy.GetClassName();
            enemyDist = possessed.Distance3D(enemy);
        }
        double cmdDist = commander ? possessed.Distance3D(commander) : -1;
        string weapName = "none";
        let pp = PlayerPawn(possessed);
        if (pp && pp.player && pp.player.ReadyWeapon)
            weapName = pp.player.ReadyWeapon.GetClassName();

        console.printf("[DC]{\"t\":\"bot_tick\",\"tic\":%d,"
            .."\"persona\":\"%s\",\"hp\":%d,"
            .."\"px\":%.0f,\"py\":%.0f,\"state\":\"%s\","
            .."\"dist_cmd\":%.0f,\"enemy\":\"%s\",\"dist_enemy\":%.0f,"
            .."\"weapon\":\"%s\"}",
            level.time, PersonaName(), possessed.health,
            possessed.pos.x, possessed.pos.y, CurrentStateName(),
            cmdDist, enemyName, enemyDist, weapName);
    }

    string CurrentStateName()
    {
        return BStateNames[bstate];
    }

    // Apply persona speed clamp. Called from DC_BotSpawner right after
    // the controller is spawned. Binds to ZetaBotPawn.speedMod, which is
    // the scalar actually consulted by BotThrust() — setting pawn.Speed
    // is a no-op since RealMoveForward/Right/Left/Backward use hard-
    // coded thrust values.
    void ApplyMovementProfile()
    {
        if (possessed == null) return;
        let zbp = ZetaBotPawn(possessed);
        if (zbp == null) return;
        zbp.speedMod = MoveSpeedMult();
    }

    // Hand the persona their loadout. Infinite-ammo sidearm via a
    // large reservoir (9999) of the sidearm's ammo type — bot will
    // never deplete it in a single map, and primaries use their own
    // disjoint ammo pools (PB_Shell, PB_HighCalMag, PB_RocketAmmo,
    // PB_Cell, PB_Fuel). Melee sidearms leave SidearmAmmoClass blank.
    void GiveLoadout()
    {
        if (possessed == null) return;

        if (PrimaryClass1() != "") possessed.GiveInventory(PrimaryClass1(), 1);
        if (PrimaryClass2() != "") possessed.GiveInventory(PrimaryClass2(), 1);
        if (SidearmClass()  != "") possessed.GiveInventory(SidearmClass(),  1);
        if (SidearmAmmoClass() != "")
            possessed.GiveInventory(SidearmAmmoClass(), 9999);

        spawnTic = level.time;

        if (DC_DebugHandler.DebugLevel() >= 1)
        {
            console.printf("[DC]{\"t\":\"bot_spawn\",\"tic\":%d,"
                .."\"persona\":\"%s\",\"hp\":%d,"
                .."\"px\":%.0f,\"py\":%.0f,"
                .."\"primary1\":\"%s\",\"primary2\":\"%s\","
                .."\"sidearm\":\"%s\","
                .."\"follow_min\":%.0f,\"follow_max\":%.0f,"
                .."\"flee_hp\":%.2f,\"can_flee\":%d,"
                .."\"move_mult\":%.2f,\"strafe_damp\":%.2f}",
                level.time, PersonaName(), possessed.health,
                possessed.pos.x, possessed.pos.y,
                PrimaryClass1(), PrimaryClass2(), SidearmClass(),
                FollowMin(), FollowMax(),
                FleeHpFrac(), CanFlee() ? 1 : 0,
                MoveSpeedMult(), StrafeDamping());
        }
    }
}
