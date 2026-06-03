@echo off
REM ============================================================
REM  Claude Desktop - attended install launcher
REM  Double-click this file. It will request admin elevation
REM  and then run Install-ClaudeDesktop.ps1 from this folder.
REM ============================================================

setlocal
set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%Install-ClaudeDesktop.ps1"

REM Check for administrator rights.
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Running Claude Desktop installer...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%errorlevel%"

echo.
echo Finished with exit code %RC%.
pause
endlocal
exit /b %RC%
