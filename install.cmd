@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
    echo [FAILED] exit code %RC% -- see the message above.
) else (
    echo [DONE]
)
pause
exit /b %RC%
