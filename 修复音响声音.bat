@echo off
chcp 65001 >nul
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Set-DefaultAudio.ps1"
echo 已把默认输出切回音响 (Realtek 2nd output)
timeout /t 2 >nul
