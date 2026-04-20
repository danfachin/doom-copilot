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
    //
    // Item 9 fix: previously did pure offset math with no collision test,
    // which wall-clipped bots on tight maps (observed 2026-04-19 w/ the
    // 4th squad member behind the player). Now probes 8 candidate
    // positions in a ring at the requested distance; if all fail, halves
    // the distance and retries; last resort is the anchor's own position
    // (guaranteed valid — the Pilot is standing there).
    void SpawnBotNear(Actor anchor, string spawnerClass, double dist, double relAngle)
    {
        Vector3 spawnPos;
        if (!FindSafeSpawn(anchor, dist, relAngle, spawnPos))
        {
            // Absolute fallback: on top of the anchor. Push-out resolves
            // the overlap in the next tic.
            spawnPos = anchor.pos;
            console.printf("\c[Orange]Doom Copilot: %s safe-spawn fallback to Pilot position",
                spawnerClass);
        }

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

    // Try the requested (dist, angle); if the point is outside the level
    // or would embed a pawn-sized actor in geometry, rotate through 7
    // other angles at the same distance, then retry the whole ring at
    // half-distance. Returns true + fills outPos on first candidate that
    // passes Level.IsPointInLevel + TestMobjLocation; false if every
    // candidate fails (caller falls back to anchor position).
    bool FindSafeSpawn(Actor anchor, double dist, double relAngle, out Vector3 outPos)
    {
        static const double RING[] = { 0, 45, -45, 90, -90, 135, -135, 180 };

        for (int pass = 0; pass < 2; pass++)
        {
            double passDist = (pass == 0) ? dist : dist * 0.5;
            for (int i = 0; i < 8; i++)
            {
                double a = anchor.angle + relAngle + RING[i];
                Vector3 candidate = anchor.pos + (passDist * cos(a), passDist * sin(a), 0);

                if (!Level.IsPointInLevel(candidate)) continue;
                if (!PointPassesPawnCheck(candidate))  continue;

                outPos = candidate;
                return true;
            }
        }
        return false;
    }

    // Probe whether a PB_PlayerPrawn-sized actor would fit at pos.
    // We do this by spawning a throwaway MapSpot-like probe actor and
    // calling TestMobjLocation, then immediately destroying it. The
    // probe inherits pawn radius/height from the default ZetaBot pawn
    // anchor so we approximate the real clearance.
    bool PointPassesPawnCheck(Vector3 pos)
    {
        // Quick cheap probe using a spare ZetaBot pawn class isn't
        // available at this layer, so we use CheckMove from the map's
        // spawn-point perspective via a temporary probe actor.
        Actor probe = Actor.Spawn("DC_SpawnProbe", pos, NO_REPLACE);
        if (probe == null) return false;
        bool ok = probe.TestMobjLocation();
        probe.Destroy();
        return ok;
    }
}

// Throwaway probe matching PB_PlayerPrawn clearance. Radius/height
// should track a PB3 player; 16×56 is the vanilla default and is
// close enough for the spawn-check use (PB3's prawn uses the same
// defaults). If this ever diverges, size to the largest persona.
class DC_SpawnProbe : Actor
{
    default
    {
        // PB_PlayerPrawn matches vanilla Doom Marine clearance (16×56);
        // if PB3 ever subclasses a taller prawn, widen this probe.
        Radius 16;
        Height 56;
        +NOGRAVITY
        +NOBLOCKMAP
    }
    states { Spawn: TNT1 A 1; Stop; }
}
