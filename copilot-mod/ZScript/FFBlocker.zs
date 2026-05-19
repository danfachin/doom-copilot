// Friendly-fire blocker for Doom Copilot.
//
// Architecture: two-layer defense.
//
// LAYER 1 — DC_FFAbsorber (Inventory.ModifyDamage, pre-damage):
//   An invisible inventory item auto-given to the Pilot on PlayerSpawned.
//   ZScript's Inventory.ModifyDamage hook fires BEFORE the damage actually
//   lands — so when a bot's rocket would do 200 dmg to a 100 HP Pilot,
//   we set newdamage=0 before the engine subtracts and triggers death.
//   This is the correct shape — no "revived corpse" / death-animation-
//   on-a-200HP-pawn edge case. Pilot doesn't visibly lose health, doesn't
//   enter Pain state, doesn't get knocked around. Total FF immunity.
//
// LAYER 2 — DC_FFBlocker.WorldThingDamaged (post-damage refund):
//   Fallback for weapon paths that bypass ModifyDamage (some PB3 weapons
//   may use direct A_DamageThing / A_RadiusGive calls that skip the
//   inventory chain). Refunds the damage if it landed. Guards against
//   reviving an already-dying Pilot: if thing.health is already <= 0
//   when this fires, we DO NOT touch it — let death proceed normally
//   (because we missed the pre-damage intercept). The fallback is
//   intentionally weaker so the cost of missing in Layer 1 is "you take
//   some damage" not "you become a zombie."
//
// Both layers only protect against damage sourced from ZetaBotPawn (the
// bot's player-pawn class). Enemy damage, Pilot self-damage, environment
// damage all pass through untouched.

class DC_FFAbsorber : Inventory
{
    Default
    {
        Inventory.Amount 1;
        Inventory.MaxAmount 1;
        +INVENTORY.UNDROPPABLE;
        +INVENTORY.UNTOSSABLE;
        +INVENTORY.UNCLEARABLE;
        +INVENTORY.PERSISTENTPOWER;
        +INVENTORY.HUBPOWER;
    }

    // Called by the engine BEFORE damage applies to the owner. Setting
    // `newdamage = 0` cancels the hit entirely — no HP change, no Pain
    // state, no death. `passive=true` means damage being received by the
    // owner; `false` would be damage being dealt out (we ignore that).
    override void ModifyDamage(int damage, Name damageType, out int newdamage,
                               bool passive, Actor inflictor = null,
                               Actor source = null, int flags = 0)
    {
        if (!passive) return;
        if (damage <= 0) return;

        // Identify the bot if it's involved. `source` is the actor that
        // "did" the damage (could be the bot or its projectile). `inflictor`
        // is the inflictor actor specifically (usually the projectile).
        // For hitscan via FireBullets, source = bot directly. For
        // projectiles, source = projectile and projectile.target = bot.
        Actor shooter = null;
        if (source && source is "ZetaBotPawn")
            shooter = source;
        else if (inflictor && inflictor.target && inflictor.target is "ZetaBotPawn")
            shooter = inflictor.target;
        else if (source && source.target && source.target is "ZetaBotPawn")
            shooter = source.target;

        if (shooter == null) return;

        newdamage = 0;

        if (DC_DebugHandler.DebugLevel() >= 1)
        {
            string shooterName = shooter.GetClassName();
            string srcName = source ? source.GetClassName() : "null";
            string infName = inflictor ? inflictor.GetClassName() : "null";
            console.printf("[DC]{\"t\":\"ff_absorb\",\"tic\":%d,"
                .."\"dmg\":%d,\"shooter\":\"%s\","
                .."\"source\":\"%s\",\"inflictor\":\"%s\"}",
                level.time, damage, shooterName, srcName, infName);
        }
    }
}

class DC_FFBlocker : EventHandler
{
    // Auto-grant the absorber to every player who spawns. Single-player
    // hits this once on level start; coop / save-load gets it on every
    // respawn. The +UNCLEARABLE / +UNDROPPABLE flags keep it sticky.
    override void PlayerSpawned(PlayerEvent e)
    {
        let mo = players[e.PlayerNumber].mo;
        if (mo && !mo.FindInventory("DC_FFAbsorber"))
        {
            mo.GiveInventory("DC_FFAbsorber", 1);
        }
    }

    // Fallback refund for damage that slipped past ModifyDamage. Skip
    // the refund when Pilot is already dying — letting death stand is
    // less broken than a 200 HP corpse mid-death-animation.
    override void WorldThingDamaged(WorldEvent e)
    {
        if (!e.thing || !e.thing.player) return;
        if (e.Damage <= 0) return;
        if (!e.DamageSource) return;

        // Don't try to refund into a dying pawn — death state already
        // armed by the engine. Layer 2 only catches survivors.
        if (e.thing.health <= 0) return;

        Actor src = e.DamageSource;
        Actor shooter = src;
        if (!(src is "ZetaBotPawn") && src.target)
            shooter = src.target;

        if (!(shooter is "ZetaBotPawn")) return;

        int refund = e.Damage;
        e.thing.health += refund;
        if (e.thing.player) e.thing.player.health = e.thing.health;

        if (DC_DebugHandler.DebugLevel() >= 1)
        {
            console.printf("[DC]{\"t\":\"ff_refund\",\"tic\":%d,"
                .."\"dmg\":%d,\"shooter\":\"%s\","
                .."\"victim_hp_after\":%d}",
                level.time, refund, shooter.GetClassName(), e.thing.health);
        }
    }
}
