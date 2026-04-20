// ZetaWeaponModule registering all PB3 weapon classes so the bot's
// weapon picker (ZetaWeaponModule.CheckType) recognizes PB3 pickups
// and returns the appropriate Zeta* class for rating + firing.
//
// Registered via zb_wtypes CVar from DC_AutoSpawnHandler. Loaded
// alongside (or ahead of) ZetaDoomWeapons so PB3 variants match
// first. Vanilla ZetaDoomWeapons stays in the chain as a fallback
// for any non-PB3 weapon that somehow survives.

class ZetaPB3Weapons : ZetaWeaponModule
{
    override void LoadWeapons(ZetaWeaponModule loader)
    {
        // Order matters for IsPickupOf dispatch: more specific
        // classes first, generic fallbacks last. Within PB3 the
        // classes are disjoint so order is cosmetic, but keep
        // heavy/specific guns first for clarity.
        loader.AddWeapon("ZetaPB3BFG");
        loader.AddWeapon("ZetaPB3RocketLauncher");
        loader.AddWeapon("ZetaPB3Plasma");
        loader.AddWeapon("ZetaPB3Minigun");
        loader.AddWeapon("ZetaPB3DMR");
        loader.AddWeapon("ZetaPB3Carbine");
        loader.AddWeapon("ZetaPB3Shotgun");
        loader.AddWeapon("ZetaPB3Flamer");
        loader.AddWeapon("ZetaPB3Sidearm");
        loader.AddWeapon("ZetaPB3Chainsaw");
        loader.AddWeapon("ZetaPB3Fists");
    }
}
