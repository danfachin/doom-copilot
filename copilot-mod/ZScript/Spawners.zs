// Spawner classes. One per persona. Summon with
//   summonfriend dc_sharpshooter 0
//   summonfriend dc_brawler 0
//   summonfriend dc_tank 0
//   summonfriend dc_deathwish 0
//
// Each spawner replicates ZetaBot's PostBeginPlay node/respawn
// bootstrapping, then spawns the persona's matching controller
// class (instead of the vanilla ZTBotController).

class DC_BotSpawner : Actor
{
    // Override per persona: returns the controller class name string.
    virtual string ControllerClass() { return "DoomCopilotController"; }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();

        // Node bootstrap — mirrors ZetaBot.PostBeginPlay. Loads saved
        // nodelist if one exists for this map; otherwise autonodes
        // picks up via zb_autonodes CVar.
        bool bHasNode;
        let ni = ThinkerIterator.create("ZTPathNode", 91);
        if (ni.Next()) bHasNode = true;

        if (!bHasNode && CVar.FindCVar("nodelist").GetString() != "::NONE")
            ZTPathNode.plopNodes(CVar.FindCVar("nodelist").GetString());

        // Spawn the persona-specific controller.
        let cont = DoomCopilotController(Spawn(ControllerClass(), pos));
        if (cont == null)
        {
            console.printf("\c[Red]Doom Copilot: failed to spawn controller %s", ControllerClass());
            return;
        }

        cont.angle = angle;
        if (cont.possessed) cont.possessed.angle = angle;

        // Announce persona to console (picked up by hearth-logger if present)
        console.printf("\c[Sapphire]Doom Copilot: deployed %s (\"%s\")",
            cont.PersonaName(),
            cont.myName != "" ? cont.myName : "unnamed");

        // Done. The spawner pawn itself has no purpose beyond bootstrapping.
        Destroy();
    }
}

class DC_Sharpshooter : DC_BotSpawner
{
    override string ControllerClass() { return "DC_SharpshooterController"; }
}

class DC_Brawler : DC_BotSpawner
{
    override string ControllerClass() { return "DC_BrawlerController"; }
}

class DC_Tank : DC_BotSpawner
{
    override string ControllerClass() { return "DC_TankController"; }
}

class DC_Deathwish : DC_BotSpawner
{
    override string ControllerClass() { return "DC_DeathwishController"; }
}
