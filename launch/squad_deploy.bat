@echo off
REM Four-God Squad Deploy
REM Runs the doom-launcher 'squad_deploy' profile:
REM   PB3 + brightmaps + Maps of Chaos + hearth-logger + zetabot-fork
REM   + hearth-silencer + copilot-mod
REM   +map MAP01 -skill 5  +dc_autospawn_squad 1
REM
REM Auto-deploys 3 bots (Sharpshooter + Tank + Brawler) on map load.
REM Hearth-logger captures telemetry. Hearth-silencer kills PB3 HUD spam.

cd /d "D:\Users\Dan\dev\doom-launcher"
set PYTHONIOENCODING=utf-8
py -3 doom_launcher.py --profile squad_deploy

pause
