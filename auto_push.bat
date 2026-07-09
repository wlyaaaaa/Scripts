@echo off
pushd "%~dp0"
git add -A
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto_push_guard.ps1"
set GUARD_EXIT=%ERRORLEVEL%
if %GUARD_EXIT% NEQ 0 (
  git reset
  popd
  exit /b %GUARD_EXIT%
)
git diff --cached --quiet
set DIFF_EXIT=%ERRORLEVEL%
if %DIFF_EXIT% EQU 0 (
  popd
  exit /b 0
)
if %DIFF_EXIT% GEQ 2 (
  popd
  exit /b %DIFF_EXIT%
)
git commit -m "auto: %DATE% %TIME%"
git push origin main
set EXIT_CODE=%ERRORLEVEL%
popd
exit /b %EXIT_CODE%
