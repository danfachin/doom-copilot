version "4.2"

// Hearth Doom Logger — invisible telemetry for AI co-op research
// Outputs structured JSON to console (captured via -logfile / +logfile)
// Prefix: [HL] — all other console output is ignored by post-processor
//
// Two sample rates:
//   state + enemy scan: LOG_INTERVAL  (2 Hz)  — semantic snapshots for the brain layer
//   player action:      ACTION_INTERVAL (~9 Hz) — dense input labels for bot tuning

class HearthLogger : EventHandler
{
    const LOG_INTERVAL    = 18;    // tics between state+enemy snapshots (~2/sec)
    const ACTION_INTERVAL = 4;     // tics between player-cmd snapshots (~8.75/sec)
    const SCAN_RADIUS     = 2048.0;
    const MAX_ENEMIES     = 20;

    int sessionKills;
    int lastLogTic;
    int lastActionTic;
    string lastWeapon;

    override void OnRegister()
    {
        sessionKills = 0;
        lastLogTic = -999;
        lastActionTic = -999;
        lastWeapon = "";
    }

    // ── Map lifecycle ──────────────────────────────────────────

    override void WorldLoaded(WorldEvent e)
    {
        sessionKills = 0;
        lastWeapon = "";
        console.printf("[HL]{\"t\":\"map_start\",\"map\":\"%s\",\"skill\":%d}",
            level.MapName, G_SkillPropertyInt(SKILLP_ACSReturn));
    }

    override void WorldUnloaded(WorldEvent e)
    {
        console.printf("[HL]{\"t\":\"map_end\",\"map\":\"%s\",\"tic\":%d,\"kills\":%d}",
            level.MapName, level.time, sessionKills);
    }

    // ── Per-tic capture ────────────────────────────────────────

    override void WorldTick()
    {
        let pmo = players[consoleplayer].mo;
        if (!pmo) return;

        TickAction(pmo);
        TickState(pmo);
    }

    // High-rate player-input capture (~9 Hz). Small payload, each row is one action frame.
    void TickAction(PlayerPawn pmo)
    {
        if (level.time - lastActionTic < ACTION_INTERVAL) return;
        lastActionTic = level.time;

        let pl = pmo.player;
        if (!pl) return;

        // Detect weapon switch (emit on change, independent of interval)
        string weapName = "None";
        if (pl.ReadyWeapon) weapName = pl.ReadyWeapon.GetClassName();
        if (weapName != lastWeapon)
        {
            console.printf("[HL]{\"t\":\"weapon_switch\",\"tic\":%d,"
                .."\"from\":\"%s\",\"to\":\"%s\"}",
                level.time, lastWeapon, weapName);
            lastWeapon = weapName;
        }

        // UserCmd fields: buttons (bitfield), forwardmove, sidemove, yaw (turn delta), pitch (look delta)
        int btn = pl.cmd.buttons;
        int fwd = pl.cmd.forwardmove;
        int side = pl.cmd.sidemove;
        int yaw = pl.cmd.yaw;
        int pitchDelta = pl.cmd.pitch;

        console.printf("[HL]{\"t\":\"action\",\"tic\":%d,"
            .."\"btn\":%d,\"fwd\":%d,\"side\":%d,\"yaw\":%d,\"pdel\":%d,"
            .."\"pa\":%.1f,\"pp\":%.1f}",
            level.time, btn, fwd, side, yaw, pitchDelta,
            pmo.angle, pmo.pitch);
    }

    // Semantic snapshot for the strategic/brain layer (~2 Hz).
    void TickState(PlayerPawn pmo)
    {
        if (level.time - lastLogTic < LOG_INTERVAL) return;
        lastLogTic = level.time;

        string weapName = "None";
        int ammoCount = 0;
        let weap = pmo.player.ReadyWeapon;
        if (weap)
        {
            weapName = weap.GetClassName();
            if (weap.Ammo1) ammoCount = weap.Ammo1.Amount;
        }

        console.printf("[HL]{\"t\":\"state\",\"tic\":%d,\"map\":\"%s\","
            .."\"px\":%.0f,\"py\":%.0f,\"pz\":%.0f,\"pa\":%.1f,\"pp\":%.1f,"
            .."\"hp\":%d,\"ar\":%d,"
            .."\"weapon\":\"%s\",\"ammo\":%d,\"kills\":%d,"
            .."\"vx\":%.0f,\"vy\":%.0f}",
            level.time, level.MapName,
            pmo.pos.x, pmo.pos.y, pmo.pos.z, pmo.angle, pmo.pitch,
            pmo.health, pmo.CountInv("BasicArmor"),
            weapName, ammoCount, sessionKills,
            pmo.vel.x, pmo.vel.y);

        int logged = 0;
        let it = ThinkerIterator.Create("Actor", STAT_DEFAULT);
        Actor mo;
        while (mo = Actor(it.Next()))
        {
            if (logged >= MAX_ENEMIES) break;
            if (!mo.bISMONSTER || mo.health <= 0) continue;

            double dist = pmo.Distance3D(mo);
            if (dist > SCAN_RADIUS) continue;

            double relAngle = pmo.AngleTo(mo) - pmo.angle;
            if (relAngle > 180) relAngle -= 360;
            if (relAngle < -180) relAngle += 360;

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

        if (e.thing.player)
        {
            string src = "world";
            if (e.DamageSource) src = e.DamageSource.GetClassName();
            console.printf("[HL]{\"t\":\"hurt\",\"tic\":%d,"
                .."\"dmg\":%d,\"src\":\"%s\",\"hp\":%d}",
                level.time, e.Damage, src, e.thing.health);
        }
    }

    override void WorldThingRevived(WorldEvent e)
    {
        if (e.thing && e.thing.bISMONSTER)
        {
            console.printf("[HL]{\"t\":\"revived\",\"tic\":%d,\"class\":\"%s\"}",
                level.time, e.thing.GetClassName());
        }
    }
}
