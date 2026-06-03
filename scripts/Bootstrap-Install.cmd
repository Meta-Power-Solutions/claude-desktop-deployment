@echo off
REM ============================================================
REM  Claude Desktop - GitHub bootstrap launcher (PUBLIC repo)
REM
REM  Double-click this file. It self-elevates, then pulls the
REM  bootstrap from the public GitHub repo, which in turn pulls
REM  and runs the installer.
REM
REM  This is the ONLY file a technician needs - it fetches the rest.
REM  Copy it via USB or download it from OneDrive, then run it.
REM
REM  Repo: https://github.com/Meta-Power-Solutions/claude-desktop-deployment
REM ============================================================

setlocal

REM Re-launch elevated if not already administrator.
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

set "OWNER=Meta-Power-Solutions"
set "REPO=claude-desktop-deployment"
set "REF=main"
set "RAW=https://raw.githubusercontent.com/%OWNER%/%REPO%/%REF%/scripts/Bootstrap-Install.ps1"
set "TMP_PS1=%TEMP%\Bootstrap-Install.ps1"

echo Pulling bootstrap from GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { (New-Object Net.WebClient).DownloadFile('%RAW%','%TMP_PS1%') } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }"
if %errorlevel% NEQ 0 (
    echo ERROR: Could not download the bootstrap. Check the network connection.
