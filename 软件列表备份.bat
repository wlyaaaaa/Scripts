@echo off
chcp 65001 >nul
title 软件列表备份
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0软件列表备份.ps1"
