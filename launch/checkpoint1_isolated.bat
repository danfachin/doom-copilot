@echo off
REM Checkpoint 1 - Test 1: ZetaBot alone in vanilla Doom 2.
REM Validates that ZetaBot compiles in UZDoom 4.14.3 without PB3 interference.
REM After level loads, drop console (backtick) and run: summonfriend zetabot 0

cd /d "D:\Users\Dan\games\DOOM\Windows-UZDoom-4.14.3"

uzdoom.exe ^
    -iwad "D:\Users\Dan\games\DOOM\Brutality\Doom2.wad" ^
    -file "D:\Users\Dan\dev\doom-copilot\zetabot-fork" ^
    +map MAP01 ^
    -skill 2 ^
    +set zb_autonodes 1 ^
    +set zb_autonodenormal 1 ^
    +set zb_autonodeuse 1

pause
