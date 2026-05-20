# Persona Calibration — empirical tuning from Dan's telemetry

Generated from 49 sessions (98 map segments, 5745 kills, 44 deaths, 707.0 min of play).

## 1. Threat weights

Ordered by damage-per-encounter. Pre-apply to `DoomCopilotController.targetPriority()` persona override.

| Class | Dmg/encounter | Weight | Dmg instances | Encounters |
|-------|---------------|--------|---------------|-----------|
| SergeantLastStand1 | 1.0 | 1.0 | 1 | 1 |
| ZetaDoom | 0.115 | 0.115 | 21 | 182 |
| ArmlessDemon | 0.077 | 0.077 | 3 | 39 |
| HelmetSergeantLastStand1 | 0.067 | 0.067 | 1 | 15 |
| HeavyMGZombieman | 0.047 | 0.047 | 4 | 86 |
| PB_Afrit | 0.025 | 0.025 | 2 | 81 |
| RevenantU | 0.022 | 0.022 | 1 | 46 |
| PB_Daedabus | 0.01 | 0.01 | 60 | 6073 |
| PB_Mancubus1 | 0.009 | 0.009 | 40 | 4526 |
| ASGGuy | 0.008 | 0.008 | 91 | 10721 |
| PB_Annihilator | 0.008 | 0.008 | 8 | 1027 |
| PB_Mastermind | 0.007 | 0.007 | 1 | 138 |
| PB_HelmetCommando | 0.007 | 0.007 | 100 | 15314 |
| PB_Zombieman | 0.006 | 0.006 | 166 | 28130 |
| PB_Commando | 0.006 | 0.006 | 175 | 29731 |
| PB_CarbineZombieman | 0.006 | 0.006 | 27 | 4764 |
| PB_PistolZombieman2 | 0.006 | 0.006 | 88 | 15651 |
| PB_CyberKnight | 0.005 | 0.005 | 58 | 12661 |
| PB_ShotgunGuy | 0.004 | 0.004 | 206 | 46680 |
| PB_HelmetZombieman | 0.004 | 0.004 | 71 | 16620 |

## 2. Weapon dwell time

How much time Dan actually spends holding each weapon. Use to decide which weapons deserve hand-tuned RateSelf curves.

| Weapon | Tics | Seconds | Dwell fraction |
|--------|------|---------|----------------|
| PB_Autoshotgun | 12235 | 349.6 | 1.0 |
| PB_Shotgun | 10699 | 305.7 | 0.874 |
| PB_Minigun | 8644 | 247.0 | 0.706 |
| PB_DMR | 8330 | 238.0 | 0.681 |
| PB_Revolver | 5706 | 163.0 | 0.466 |
| PB_Deagle | 4452 | 127.2 | 0.364 |
| PB_RocketLauncher | 4149 | 118.5 | 0.339 |
| PB_SuperGL | 3511 | 100.3 | 0.287 |
| PB_SSG | 2703 | 77.2 | 0.221 |
| PB_Carbine | 2007 | 57.3 | 0.164 |
| PB_M1Plasma | 1793 | 51.2 | 0.147 |
| PB_Nailgun | 1611 | 46.0 | 0.132 |
| PB_Pistol | 1514 | 43.3 | 0.124 |
| PB_LMG | 1505 | 43.0 | 0.123 |
| PB_Flamethrower | 1447 | 41.3 | 0.118 |
| PB_Railgun | 1344 | 38.4 | 0.11 |
| PB_Chainsaw | 992 | 28.3 | 0.081 |
| PB_BFG9000 | 872 | 24.9 | 0.071 |
| PB_SMG | 776 | 22.2 | 0.063 |
| PB_QuadSG | 616 | 17.6 | 0.05 |
| PB_M2Plasma | 579 | 16.5 | 0.047 |
| PB_Axe | 284 | 8.1 | 0.023 |
| PB_Fists | 115 | 3.3 | 0.009 |
| Fist | 12 | 0.3 | 0.001 |
| Pistol | 3 | 0.1 | 0.0 |

## 3. Flee-HP thresholds

- Sampled **44 deaths**
- Median HP at death: **10**
- Survival low-water — p50: 76, p25: 52, p10: 31

### Suggested persona flee thresholds (override FleeHpFrac):
- **Tank** (safe): `return 0.76;`
- **Sharpshooter** (moderate): `return 0.64;`
- **Brawler** (aggressive): `return 0.31;`
- **Death-Wish**: CanFlee() = false (unchanged)

## 4. Engagement ranges by weapon

The empirical range at which kills happen for each weapon. Use to calibrate `RateSelf` curve peaks in `PB3Weapons.zs`.

| Weapon | Kills sampled | p25 | Median | p75 | Mean |
|--------|---------------|-----|--------|-----|------|
| PB_Autoshotgun | 1560 | 197 | 293 | 456 | 371 |
| PB_Minigun | 1176 | 211 | 333 | 527 | 399 |
| PB_Shotgun | 1087 | 189 | 286 | 433 | 352 |
| PB_DMR | 958 | 172 | 232 | 422 | 344 |
| PB_RocketLauncher | 597 | 268 | 391 | 608 | 468 |
| PB_SuperGL | 585 | 220 | 317 | 496 | 395 |
| PB_BFG9000 | 480 | 246 | 506 | 753 | 524 |
| PB_Deagle | 436 | 191 | 297 | 473 | 347 |
| PB_Revolver | 434 | 178 | 285 | 499 | 370 |
| PB_SSG | 371 | 202 | 314 | 483 | 396 |
| PB_Carbine | 242 | 283 | 579 | 1052 | 634 |
| PB_Nailgun | 210 | 245 | 329 | 535 | 411 |
| PB_M1Plasma | 174 | 184 | 314 | 557 | 430 |
| PB_Flamethrower | 141 | 260 | 415 | 693 | 500 |
| PB_Chainsaw | 116 | 50 | 89 | 199 | 158 |
| PB_Pistol | 98 | 164 | 249 | 405 | 318 |
| PB_SMG | 93 | 184 | 277 | 492 | 379 |
| PB_LMG | 90 | 115 | 188 | 341 | 260 |
| PB_Railgun | 79 | 324 | 455 | 665 | 516 |
| PB_QuadSG | 59 | 118 | 163 | 236 | 248 |
| PB_M2Plasma | 53 | 277 | 332 | 500 | 381 |
| PB_Axe | 25 | 100 | 135 | 446 | 284 |
| PB_Fists | 5 | 217 | 242 | 245 | 424 |
