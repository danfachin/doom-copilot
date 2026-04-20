version "4.14.2"

// Doom Copilot — persona-driven bot companions on top of ZetaBot.
//
// Architecture:
//   DoomCopilotController : ZTBotController
//     Base controller that exposes virtual hooks for persona dials
//     (follow distance, flee threshold, aim precision, etc.) and
//     overrides ZetaBot's key subroutines to consult them.
//
//   Four subclasses — one per persona — each override the virtual
//   hooks with their numeric profile:
//     DC_SharpshooterController  (ranged, overwatch, high aim skill)
//     DC_BrawlerController       (close-range, aggressive, low-skill-high-volume)
//     DC_TankController          (body-block near player, high survivability)
//     DC_DeathwishController     (no-retreat, always-advance, chaotic)
//
//   Four spawner wrappers (DC_Sharpshooter etc.) that Dan summons from
//   console or keybind: `summonfriend dc_sharpshooter 0` etc. Each
//   spawner hands off to its matching controller class.
//
// Load order: zetabot-fork/ → copilot-mod/

#include "ZScript/WeaponModule/PB3Weapons.zs"
#include "ZScript/WeaponModule/ZetaPB3Weapons.zs"
#include "ZScript/DoomCopilotController.zs"
#include "ZScript/PersonaControllers.zs"
#include "ZScript/Spawners.zs"
#include "ZScript/AutoSpawner.zs"
