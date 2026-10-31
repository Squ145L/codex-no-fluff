@echo off
chcp 65001 >nul
echo This restores your previous Codex config.toml.
echo Press Ctrl+C to cancel, or any key to continue.
pause >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Rollback
echo.
pause
