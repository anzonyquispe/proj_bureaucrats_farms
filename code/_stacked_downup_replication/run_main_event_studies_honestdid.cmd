@echo off
setlocal
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_main_event_studies_honestdid.ps1"
exit /b %errorlevel%
