version "4.2"

// Hearth Doom Logger — invisible telemetry for AI co-op research
// Outputs structured JSON to console (captured via -logfile)
// Prefix: [HL] — all other console output is ignored by post-processor

class HearthLogger : EventHandler
{
    const LOG_INTERVAL = 18;    // tics between state snapshots (~2/sec at 35 tic/sec)
    const SCAN_RADIUS = 2048.0; // map units — covers most combat encounters
    const MAX_ENEMIES = 20;     // cap per snapshot to limit log volume

    int sessionKills;
    int lastLogTic;

    override void OnRegister()
    {
        sessionKills = 0;
        lastLogTic = -999;
    }

    // ── Map lifecycle ──────────────────────────────────────────

    override void WorldLoaded(WorldEvent e)
    {
        sessionKills = 0;
        console.printf("[HL]{\"t\":\"map_start\",\"map\":\"%s\",\"skill\":%d}",
            level.MapName, G_SkillPropertyInt(SKILLP_ACSReturn));
    }

    override void WorldUnloaded(WorldEvent e)
    {
        console.printf("[HL]{\"t\":\"map_end\",\"map\":\"%s\",\"tic\":%d,\"kills\":%d}",
            level.MapName, level.time, sessionKills);
    }

    // ── Per-tic state capture ──────────────────────────────────

    override void WorldTick()
    {
        if (level.time - lastLogTic < LOG_INTERVAL) return;
        lastLogTic = level.time;

        let pmo = players[consoleplayer].mo;
        if (!pmo) return;

        // Weapon + ammo
        string weapName = "None";
        int ammoCount = 0;
        let weap = pmo.player.ReadyWeapon;
        if (weap)
        {
            weapName = weap.GetClassName();
            if (weap.Ammo1) ammoCount = weap.Ammo1.Amount;
        }

        // Player state snapshot
        console.printf("[HL]{\"t\":\"state\",\"tic\":%d,\"map\":\"%s\","
            .."\"px\":%.0f,\"py\":%.0f,\"pz\":%.0f,\"pa\":%.1f,"
            .."\"hp\":%d,\"ar\":%d,"
            .."\"weapon\":\"%s\",\"ammo\":%d,\"kills\":%d,"
            .."\"vx\":%.0f,\"vy\":%.0f}",
            level.time, level.MapName,
            pmo.pos.x, pmo.pos.y, pmo.pos.z, pmo.angle,
            pmo.health, pmo.CountInv("BasicArmor"),
            weapName, ammoCount, sessionKills,
            pmo.vel.x, pmo.vel.y);

        // Scan nearby living enemies
        int logged = 0;
        let it = ThinkerIterator.Create("Actor");
        Actor mo;
        while (mo = Actor(it.Next()))
        {
            if (logged >= MAX_ENEMIES) break;
            if (!mo.bISMONSTER || mo.health <= 0) continue;

            double dist = pmo.Distance3D(mo);
            if (dist > SCAN_RADIUS) continue;

            double relAngle = deltaangle(pmo.angle, pmo.AngleTo(mo));

            // Classify enemy behavior state
            string mstate = "idle";
            if (mo.SeeState && mo.InStateSequence(mo.CurState, mo.SeeState))
                mstate = "chase";
            if (mo.MissileState && mo.InStateSequence(mo.CurState, mo.MissileState))
                mstate = "missile";
            if (mo.MeleeState && mo.InStateSequence(mo.CurState, mo.MeleeState))
                mstate = "melee";

            console.printf("[HL]{\"t\":\"enemy\",\"tic\":%d,"
                .."\"class\":\"%s\",\"dist\":%.0f,\"angle\":%.1f,"
                .."\"hp\":%d,\"maxhp\":%d,\"state\":\"%s\"}",
                level.time, mo.GetClassName(), dist, relAngle,
                mo.health, mo.SpawnHealth(), mstate);

            logged++;
        }
    }

    // ── Combat events ──────────────────────────────────────────

    override void WorldThingDied(WorldEvent e)
    {
        if (!e.thing) return;

        // Monster killed
        if (e.thing.bISMONSTER)
        {
            sessionKills++;
            string killer = "unknown";
            if (e.thing.target) killer = e.thing.target.GetClassName();
            console.printf("[HL]{\"t\":\"kill\",\"tic\":%d,"
                .."\"class\":\"%s\",\"maxhp\":%d,\"killer\":\"%s\"}",
                level.time, e.thing.GetClassName(),
                e.thing.SpawnHealth(), killer);
        }

        // Player died
        if (e.thing.player)
        {
            string killedBy = "unknown";
            if (e.thing.target) killedBy = e.thing.target.GetClassName();
            console.printf("[HL]{\"t\":\"player_death\",\"tic\":%d,"
                .."\"killed_by\":\"%s\",\"map\":\"%s\",\"kills\":%d}",
                level.time, killedBy, level.MapName, sessionKills);
        }
    }

    override void WorldThingDamaged(WorldEvent e)
    {
        if (!e.thing) return;

        // Player took damage
        if (e.thing.player)
        {
            string src = "world";
            if (e.DamageSource) src = e.DamageSource.GetClassName();
            console.printf("[HL]{\"t\":\"hurt\",\"tic\":%d,"
                .."\"dmg\":%d,\"src\":\"%s\",\"hp\":%d}",
                level.time, e.Damage, src, e.thing.health);
        }
    }

    // ── Item pickups ───────────────────────────────────────────

    override void WorldThingRevived(WorldEvent e)
    {
        // Archvile resurrections — important tactical event
        if (e.thing && e.thing.bISMONSTER)
        {
            console.printf("[HL]{\"t\":\"revived\",\"tic\":%d,\"class\":\"%s\"}",
                level.time, e.thing.GetClassName());
        }
    }
}
