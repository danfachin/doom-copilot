// Doom Copilot squad telemetry.
//
// Gated by CVar dc_debug (0/1/2). Emits structured `[DC]` lines to the
// GZDoom console — the launch .bat writes console output to logfile, so
// every event here ends up in the same logfile as hearth-logger's [HL]
// events. Grep after a run to see what each persona actually did.
//
// Event schema (all JSON-ish, `[DC]` prefix):
//   bot_spawn    persona, name, pos, primaries, sidearm, follow_min/max
//   state_change persona, from, to, hp, dist_cmd, enemy, dist_enemy
//   bot_hurt     persona, hp_after, dmg, src          (dc_debug >= 1)
//   bot_death    persona, killer, tic_alive, final_state
//   bot_tick     persona, hp, pos, state, dist_cmd,
//                enemy, dist_enemy, weapon            (dc_debug >= 2, ~2Hz)
//
// `state_change` is the single most useful signal for "why is the bot
// doing this" — a Sharpshooter that flips to ATTACKING at 200u when
// we wanted 1000u tells us EngagementRange isn't getting consulted,
// etc. Pair it with bot_hurt to see "state flipped to ATTACKING two
// tics before taking 45 damage."

class DC_DebugHandler : EventHandler
{
    const TICK_INTERVAL = 18;   // 2 Hz — matches hearth-logger state rate

    int lastTickTic;

    override void OnRegister()
    {
        lastTickTic = -999;
    }

    static int DebugLevel()
    {
        let cv = CVar.FindCVar("dc_debug");
        return cv ? cv.GetInt() : 0;
    }

    // Find the DC controller whose possessed pawn is `pawn`, or null.
    // Cheap enough for damage/death hooks — there are at most 4 bots.
    static DoomCopilotController FindController(Actor pawn)
    {
        if (!pawn) return null;
        let it = ThinkerIterator.Create("DoomCopilotController");
        DoomCopilotController cont;
        while (cont = DoomCopilotController(it.Next()))
        {
            if (cont.possessed == pawn) return cont;
        }
        return null;
    }

    override void WorldThingDamaged(WorldEvent e)
    {
        if (DebugLevel() < 1) return;
        if (!e.thing) return;

        let cont = FindController(e.thing);
        if (!cont) return;

        string src = "world";
        if (e.DamageSource) src = e.DamageSource.GetClassName();

        console.printf("[DC]{\"t\":\"bot_hurt\",\"tic\":%d,"
            .."\"persona\":\"%s\",\"hp\":%d,\"dmg\":%d,\"src\":\"%s\"}",
            level.time, cont.PersonaName(),
            e.thing.health, e.Damage, src);
    }

    override void WorldThingDied(WorldEvent e)
    {
        if (!e.thing) return;

        let cont = FindController(e.thing);
        if (!cont) return;

        string killer = "unknown";
        if (e.thing.target) killer = e.thing.target.GetClassName();

        int tic_alive = (cont.spawnTic > 0) ? (level.time - cont.spawnTic) : -1;

        console.printf("[DC]{\"t\":\"bot_death\",\"tic\":%d,"
            .."\"persona\":\"%s\",\"killer\":\"%s\",\"tic_alive\":%d,"
            .."\"final_state\":\"%s\"}",
            level.time, cont.PersonaName(), killer, tic_alive,
            cont.CurrentStateName());
    }

    override void WorldTick()
    {
        if (DebugLevel() < 2) return;
        if (level.time - lastTickTic < TICK_INTERVAL) return;
        lastTickTic = level.time;

        let it = ThinkerIterator.Create("DoomCopilotController");
        DoomCopilotController cont;
        while (cont = DoomCopilotController(it.Next()))
        {
            if (!cont.possessed || cont.possessed.health <= 0) continue;
            cont.EmitTickLog();
        }
    }
}
