# Persona Calibration — empirical tuning from Dan's telemetry

Generated from 6 sessions (17 map segments, 1441 kills, 7 deaths, 118.7 min of play).

## 1. Threat weights

Ordered by damage-per-encounter. Pre-apply to `DoomCopilotController.targetPriority()` persona override.

| Class | Dmg/encounter | Weight | Dmg instances | Encounters |
|-------|---------------|--------|---------------|-----------|
| HelmetSergeantLastStand1 | 0.083 | 1.0 | 1 | 12 |
| PB_InfernalArachnotron | 0.021 | 0.253 | 2 | 95 |
| PB_Daedabus | 0.019 | 0.227 | 18 | 951 |
| PB_PistolZombieman2 | 0.015 | 0.179 | 49 | 3290 |
| ASGGuy | 0.014 | 0.172 | 15 | 1049 |
| PB_HelmetCommando | 0.011 | 0.127 | 25 | 2368 |
| PB_Commando | 0.01 | 0.119 | 52 | 5232 |
| PB_Phantasm | 0.009 | 0.109 | 6 | 660 |
| PB_CyberKnight | 0.009 | 0.105 | 30 | 3431 |
| PB_HelmetZombieman | 0.008 | 0.097 | 31 | 3846 |
| PB_Zombieman | 0.007 | 0.079 | 43 | 6528 |
| PB_ShotgunGuy | 0.007 | 0.078 | 56 | 8594 |
| PB_Knight | 0.006 | 0.069 | 12 | 2100 |
| PB_CyberBaron | 0.006 | 0.067 | 9 | 1606 |
| PB_BeamRev | 0.005 | 0.057 | 2 | 422 |
| PB_ShotgunGuyHelmet | 0.004 | 0.043 | 71 | 19985 |
| PB_CarbineZombieman | 0.003 | 0.038 | 7 | 2216 |
| DNImpVariant2 | 0.002 | 0.023 | 28 | 14721 |
| PB_PistolZombieman1 | 0.002 | 0.022 | 8 | 4383 |
| PB_Spectre | 0.002 | 0.02 | 8 | 4893 |

## 2. Weapon dwell time

How much time Dan actually spends holding each weapon. Use to decide which weapons deserve hand-tuned RateSelf curves.

| Weapon | Tics | Seconds | Dwell fraction |
|--------|------|---------|----------------|
| PB_Shotgun | 3594 | 102.7 | 1.0 |
| PB_Minigun | 1734 | 49.5 | 0.482 |
| PB_DMR | 1456 | 41.6 | 0.405 |
| PB_SSG | 1294 | 37.0 | 0.36 |
| PB_Autoshotgun | 944 | 27.0 | 0.263 |
| PB_Carbine | 938 | 26.8 | 0.261 |
| PB_Revolver | 909 | 26.0 | 0.253 |
| PB_RocketLauncher | 796 | 22.7 | 0.221 |
| PB_Pistol | 678 | 19.4 | 0.189 |
| PB_Flamethrower | 515 | 14.7 | 0.143 |
| PB_Chainsaw | 479 | 13.7 | 0.133 |
| PB_BFG9000 | 253 | 7.2 | 0.07 |
| PB_M2Plasma | 243 | 6.9 | 0.068 |
| PB_Axe | 103 | 2.9 | 0.029 |
| PB_M1Plasma | 64 | 1.8 | 0.018 |
| PB_Fists | 35 | 1.0 | 0.01 |

## 3. Flee-HP thresholds

- Sampled **7 deaths**
- Median HP at death: **10**
- Survival low-water — p50: 78, p25: 60, p10: 41

### Suggested persona flee thresholds (override FleeHpFrac):
- **Tank** (safe): `return 0.78;`
- **Sharpshooter** (moderate): `return 0.69;`
- **Brawler** (aggressive): `return 0.41;`
- **Death-Wish**: CanFlee() = false (unchanged)

## 4. Engagement ranges by weapon

The empirical range at which kills happen for each weapon. Use to calibrate `RateSelf` curve peaks in `PB3Weapons.zs`.

| Weapon | Kills sampled | p25 | Median | p75 | Mean |
|--------|---------------|-----|--------|-----|------|
| PB_Shotgun | 367 | 189 | 287 | 405 | 331 |
| PB_Minigun | 307 | 248 | 347 | 625 | 440 |
| PB_SSG | 195 | 199 | 300 | 489 | 405 |
| PB_RocketLauncher | 178 | 288 | 337 | 547 | 437 |
| PB_DMR | 174 | 174 | 224 | 395 | 307 |
| PB_BFG9000 | 131 | 131 | 204 | 375 | 297 |
| PB_Carbine | 131 | 254 | 836 | 1158 | 721 |
| PB_Autoshotgun | 102 | 221 | 281 | 434 | 356 |
| PB_Revolver | 74 | 288 | 539 | 897 | 600 |
| PB_Pistol | 55 | 158 | 233 | 349 | 277 |
| PB_Chainsaw | 55 | 47 | 65 | 139 | 156 |
| PB_Flamethrower | 40 | 180 | 264 | 1110 | 568 |
| PB_Axe | 12 | 125 | 204 | 749 | 393 |
| PB_M2Plasma | 12 | 207 | 235 | 319 | 274 |
