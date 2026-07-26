@echo off
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PWSH%" (
  "%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sync-DocumentsToG.ps1"
) else (
  echo [ERROR] PowerShell 7 is required: "%PWSH%"
  exit /b 70
)
pause
