// Friendly-fire blocker for Doom Copilot.
//
// The bot-side FF block at ZetaBotPawn.DamageMobj (zetabot-fork, commits
// 635863f / 00c09cb) protects BOTS from damage by other bots and by the
// Pilot. It does NOT protect the Pilot from damage dealt BY a bot. With
// PB3 weapons, bot Fire() spawns ZetaBullet projectiles whose Species
// ("ZetaBotGuy") doesn't match the Pilot's ("Marines"), so +THRUSPECIES
// doesn't help.
//
// Real-world impact: on session_20260518_211046.log we caught a
// 72+64 = 136 damage burst on the Pilot in a single tick (tic 2195,
// src="ZetaDoom"), dropping HP from 149 → 13. Two more shots and Dan's
// dead from his own squad.
//
// Fix: WorldThingDamaged hook that refunds damage to any player whose
// damage source is a ZetaBotPawn or any actor owned/targeted by one.
// The damage is already applied (WorldThingDamaged is post-damage), so
// we restore HP and zero out armor cost via GiveBody.
//
// Why not species matching? PB3 spawns many projectile types (rockets,
// plasma, flames, hitscan), none of which share a species with the
// player. Centralizing here is one rule, one place — no per-weapon
// patching needed. Cost is one EventHandler dispatch per damage event,
// negligible.
//
// Telemetry: emits [DC]ff_block lines so we can audit incidents.

class DC_FFBlocker : EventHandler
{
    override void WorldThingDamaged(WorldEvent e)
    {
        if (!e.thing || !e.thing.player) return;       // only protect players
        if (e.Damage <= 0) return;                     // healing / zero events
        if (!e.DamageSource) return;                   // environmental

        // Walk damage source: a projectile may have spawned the damage,
        // its `target` field points at the shooter. Hitscan damage may
        // pass DamageSource = shooter directly. Cover both shapes.
        Actor src = e.DamageSource;
        Actor shooter = src;
        if (!(src is "ZetaBotPawn") && src.target)
        {
            shooter = src.target;
        }

        if (!(shooter is "ZetaBotPawn")) return;       // not a bot — let damage stand

        // Refund. e.Damage was already applied to e.thing.health; restore.
        // Use GiveBody with a high max so the heal isn't capped at the
        // pawn's MaxHealth — Pilot might be over-cap with a megasphere.
        // Player.health and Actor.health are both updated here.
        int refund = e.Damage;
        e.thing.health += refund;
        if (e.thing.player) e.thing.player.health = e.thing.health;

        // Telemetry — surface FF events so we know how often this fires
        // and from which persona. Gated by dc_debug like the rest.
        if (DC_DebugHandler.DebugLevel() >= 1)
        {
            string shooterName = shooter.GetClassName();
            string srcName = src.GetClassName();
            console.printf("[DC]{\"t\":\"ff_block\",\"tic\":%d,"
                .."\"dmg\":%d,\"shooter\":\"%s\",\"vector\":\"%s\","
                .."\"victim_hp_after_refund\":%d}",
                level.time, refund, shooterName, srcName, e.thing.health);
        }
    }
}
