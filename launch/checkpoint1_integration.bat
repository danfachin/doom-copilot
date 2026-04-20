@echo off
REM Checkpoint 1 - Test 2: Full load chain (PB3 + logger + silencer + ZetaBot).
REM Validates that all four mods coexist and that Hearth Silencer kills
REM the PB3 HUD message spam. After level loads: summonfriend zetabot 0

cd /d "D:\Users\Dan\games\DOOM\Windows-UZDoom-4.14.3"

uzdoom.exe ^
    -iwad "D:\Users\Dan\games\DOOM\Brutality\Doom2.wad" ^
    -file "D:\Users\Dan\games\DOOM\Project_Brutality-master" ^
           "D:\Users\Dan\dev\doom-copilot\zetabot-fork" ^
           "D:\Users\Dan\dev\doom-copilot\logger\hearth-logger" ^
           "D:\Users\Dan\dev\doom-copilot\hearth-silencer" ^
    +map MAP01 ^
    -skill 2 ^
    +set zb_autonodes 1 ^
    +set zb_autonodenormal 1 ^
    +set zb_autonodeuse 1 ^
    +logfile "D:\Users\Dan\dev\doom-copilot\data\session_checkpoint1.log"

pause
