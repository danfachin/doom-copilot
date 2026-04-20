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
// Override pattern: we subclass key ZTBotController methods. ZetaBot's
// methods are not declared `virtual` in all cases, so where ZScript
// allows override by matching signature we do; where not, we duplicate
// the method body with persona-aware tweaks. Current overrides:
//   - ShouldFollow (uses FollowMin/FollowMax)
//   - Subroutine_Flee (uses FleeHpFrac, FleeEnemyDist, CanFlee)
//   - RefreshSkills (applies AimScatterMult, TurnSpeedMult to CVars)

class DoomCopilotController : ZTBotController
{
    // ── Persona identity ───────────────────────────────────────

    virtual string PersonaName()       { return "Generic"; }

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
}
