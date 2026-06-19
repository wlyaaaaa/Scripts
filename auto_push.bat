@echo off
cd /d E:\Scripts
git add -A
git diff --cached --quiet && exit /b 0
git commit -m "auto: %DATE% %TIME%"
git push origin main
