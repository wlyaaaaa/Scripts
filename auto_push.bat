@echo off
setlocal
pushd "%~dp0"
git diff --cached --quiet
set INDEX_EXIT=%ERRORLEVEL%
if %INDEX_EXIT% EQU 1 (
  echo [BLOCK] Existing staged changes are user-owned; auto push left them untouched.
  popd
  exit /b 32
)
if %INDEX_EXIT% GEQ 2 (
  popd
  exit /b %INDEX_EXIT%
)
git add -A
if errorlevel 1 (
  popd
  exit /b 30
)
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto_push_guard.ps1"
set GUARD_EXIT=%ERRORLEVEL%
if %GUARD_EXIT% NEQ 0 (
  git reset --quiet
  popd
  exit /b %GUARD_EXIT%
)
git diff --cached --quiet
set DIFF_EXIT=%ERRORLEVEL%
if %DIFF_EXIT% GEQ 2 (
  popd
  exit /b %DIFF_EXIT%
)
if %DIFF_EXIT% EQU 1 (
  git commit -m "auto: %DATE% %TIME%"
  if errorlevel 1 (
    popd
    exit /b 31
  )
)
git push origin HEAD:refs/heads/main
set EXIT_CODE=%ERRORLEVEL%
if %EXIT_CODE% NEQ 0 (
  popd
  exit /b %EXIT_CODE%
)
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto_push_guard.ps1" -VerifyRemote
set EXIT_CODE=%ERRORLEVEL%
popd
exit /b %EXIT_CODE%
