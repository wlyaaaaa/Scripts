@echo off
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PWSH%" (
  "%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-DownloadsToG.ps1"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-DownloadsToG.ps1"
)
pause

