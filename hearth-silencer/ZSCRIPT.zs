version "4.14.2"

// Hearth Silencer — kills PB3's HUD message spam.
//
// Root cause: PB_Hud_ZS (Project Brutality's StatusBar) overrides
// ProcessNotify() and ProcessMidPrint() to intercept every print call
// into its own MainQueue with hardcoded durations (MSGDURATION=5s,
// CHATDURATION=25s, PICKDURATION=3s). That's why con_notifytime,
// con_midtime, msg, and msgcolors CVars never worked — PB3 captures
// prints before the engine checks those CVars.
//
// Fix: subclass PB_Hud_ZS, re-override those two hooks to return true
// (swallow) for everything except PRINT_CHAT. Chat stays visible for
// multiplayer + future VGS callouts. MAPINFO swaps StatusBarClass
// to this subclass, loaded AFTER PB3.
//
// Preserves: all of PB3's HUD rendering (health bars, ammo, keys, etc.)
// Kills: pickup spam, weapon-swap feedback, PBMonsterArmor "armor
//        destroyed" messages, debug traces, hearth-logger [HL] prints
//        bleeding into the HUD.

class Hearth_SilentHud : PB_Hud_ZS
{
    override bool ProcessNotify(EPrintLevel printlevel, string outline)
    {
        // Let chat and team-chat through (PRINT_CHAT / PRINT_TEAMCHAT)
        int rprint = printlevel & PRINT_TYPES;
        if (rprint == PRINT_CHAT || rprint == PRINT_TEAMCHAT)
            return super.ProcessNotify(printlevel, outline);
        // Swallow everything else — prevent MainQueue enqueue
        return true;
    }

    override bool ProcessMidPrint(font fnt, string msg, bool bold)
    {
        // Suppress mid-screen messages entirely. If we later want a
        // subset (e.g. boss bars, level titles), gate by content here.
        return true;
    }
}
