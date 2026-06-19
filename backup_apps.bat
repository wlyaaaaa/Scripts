@echo off
chcp 65001 >nul
title Backup Apps
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup_apps.ps1"
echo.
pause
