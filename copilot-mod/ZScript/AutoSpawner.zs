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

        Actor spawner = Spawn(spawnerClass, spawnPos, ALLOW_REPLACE);
        if (!spawner)
        {
            console.printf("\c[Red]Doom Copilot: Spawn(%s) returned null", spawnerClass);
            return;
        }
        spawner.angle = anchor.angle;
    }
}
