// Squad auto-spawner. When the CVar dc_autospawn_squad is 1, deploys
// the three-bot squad (Sharpshooter + Tank + Brawler) ~1 second after
// WorldLoaded fires. The delay gives the player pawn time to fully
// spawn so PickCommander in the controllers finds them.
//
// Player flavor = Deathwish by implication (the Pilot brings the
// chaos, the bots bring discipline). Change the squad composition
// by editing DeploySquad() below.
//
// Set from launcher preset's extra_args: +set dc_autospawn_squad 1
// Leave at 0 for manual F5/F6/F7/F8/F9 keybind summons.

class DC_AutoSpawnHandler : EventHandler
{
    const DEPLOY_DELAY_TICS = 35;  // 1 second after map load

    int deployTic;
    bool deployed;

    override void OnRegister()
    {
        deployTic = -1;
        deployed = false;
        EnsurePB3BotTypeAnchor();
        EnsurePB3WeaponModule();
    }

    // Ensure our PB3 weapon module is first in zb_wtypes so the bot
    // recognizes PB_Shotgun/PB_Minigun/etc. as pickable weapons with
    // proper range ratings. Idempotent.
    void EnsurePB3WeaponModule()
    {
        let cv = CVar.GetCVar("zb_wtypes");
        if (!cv) return;
        string cur = cv.GetString();
        if (cur.IndexOf("ZetaPB3Weapons") >= 0) return;
        string patched = "ZetaPB3Weapons;" .. cur;
        cv.SetString(patched);
        console.printf("\c[Sapphire]Doom Copilot: registered PB3 weapon module in zb_wtypes");
    }

    // Ensure ZetaBot's pawn-type picker recognizes PB3's player class.
    // Without this, summoning a bot under PB3 fails silently (controller
    // spawns with null possessed). Idempotent — only prepends if missing.
    //
    // We do this from ZScript instead of a launcher +set arg because
    // GZDoom's command-line handler splits CVar values on ';', which
    // corrupts the zb_btypes string.
    void EnsurePB3BotTypeAnchor()
    {
        let cv = CVar.GetCVar("zb_btypes");
        if (!cv) return;
        string cur = cv.GetString();
        if (cur.IndexOf("PB_PlayerPrawn") >= 0) return;
        string patched = "ZetaDoom:PB_PlayerPrawn;" .. cur;
        cv.SetString(patched);
        console.printf("\c[Sapphire]Doom Copilot: registered PB_PlayerPrawn anchor in zb_btypes");
    }

    override void WorldLoaded(WorldEvent e)
    {
        deployTic = -1;
        deployed = false;
        if (!CVar.FindCVar("dc_autospawn_squad").GetBool()) return;
        // Defer to WorldTick so the player has spawned and we can pick
        // a commander nearby.
        deployTic = DEPLOY_DELAY_TICS;
    }

    override void WorldTick()
    {
        if (deployed || deployTic < 0) return;

        if (level.time < deployTic) return;
        deployed = true;
        DeploySquad();
    }

    void DeploySquad()
    {
        let pmo = players[consoleplayer].mo;
        if (!pmo)
        {
            console.printf("\c[Red]Doom Copilot auto-spawn: no player pawn yet, skipping deploy.");
            return;
        }

        console.printf("\c[Sapphire]Doom Copilot: auto-deploying squad at Pilot position");

        SpawnBotNear(pmo, "DC_Sharpshooter", 96.0,  45.0);
        SpawnBotNear(pmo, "DC_Tank",         96.0, -45.0);
        SpawnBotNear(pmo, "DC_Brawler",      96.0, 180.0);
    }

    // Spawn a bot spawner actor offset from the player by (dist, relAngle).
    void SpawnBotNear(Actor anchor, string spawnerClass, double dist, double relAngle)
    {
        double a = anchor.angle + relAngle;
        Vector3 offset = (dist * cos(a), dist * sin(a), 0);
        Vector3 spawnPos = anchor.pos + offset;

        // replace param omitted → defaults to NO_REPLACE. Our DC_ spawners
        // aren't subject to class replacement so this is fine.
        Actor botSpawner = Actor.Spawn(spawnerClass, spawnPos);
        if (!botSpawner)
        {
            console.printf("\c[Red]Doom Copilot: Spawn(%s) returned null", spawnerClass);
            return;
        }
        botSpawner.angle = anchor.angle;
    }
}
