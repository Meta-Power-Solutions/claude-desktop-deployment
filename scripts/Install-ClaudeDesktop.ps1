<#
.SYNOPSIS
    Attended installer for Claude Desktop on managed Windows endpoints.

.DESCRIPTION
    Installs Claude Desktop machine-wide (all users) using the enterprise MSIX
    package, and enables the Virtual Machine Platform feature required for Cowork.

    Designed for a technician sitting at the user's desktop. Run elevated.
    Later, the same MSIX + provisioning approach can be packaged for Intune/SCCM.

    Steps performed:
      1. Verify the session is elevated (administrator).
      2. Detect CPU architecture (x64 / arm64).
      3. Optionally enable the Virtual Machine Platform feature (for Cowork).
      4. Acquire the MSIX (local -MsixPath, or download the latest from Anthropic).
      5. Provision the package machine-wide (Add-AppxProvisionedPackage).
      6. Verify the install and report whether a reboot is required.

    All actions are written to a timestamped log file.

.PARAMETER MsixPath
    Path to a local Claude MSIX package. If omitted, the latest package for the
    detected architecture is downloaded from Anthropic.

.PARAMETER Architecture
    Force a target architecture: x64 or arm64. Default: auto-detect.

.PARAMETER SkipVmPlatform
    Skip enabling the Virtual Machine Platform feature. Cowork will not work
    until that feature is enabled separately.

.PARAMETER LogPath
    Folder for the log file. Default: the folder this script runs from.

.EXAMPLE
    # Download latest and install machine-wide, enabling Cowork prerequisites:
    powershell -ExecutionPolicy Bypass -File .\Install-ClaudeDesktop.ps1

.EXAMPLE
    # Install from a pre-downloaded package (offline / locked-down network):
    .\Install-ClaudeDesktop.ps1 -MsixPath "C:\Deploy\Claude.msix"

.NOTES
    Requires: Windows 10 1903+ / Windows 11, x64 or arm64, administrator rights.
    Central deployment and policy control require a Team or Enterprise plan.
    Reference: https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$MsixPath,

    [ValidateSet('x64', 'arm64')]
    [string]$Architecture,

    [switch]$SkipVmPlatform,

    [string]$LogPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# --- Constants -------------------------------------------------------------
$DownloadUrls = @{
    'x64'   = 'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect'
    'arm64' = 'https://claude.ai/api/desktop/win32/arm64/msix/latest/redirect'
}
$PackageNameMatch = '*Claude*'   # used to locate the installed package for verification

# --- Logging ---------------------------------------------------------------
if (-not $LogPath) { $LogPath = (Get-Location).Path }
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$LogFile = Join-Path $LogPath ("Install-ClaudeDesktop_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Write-Log {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')] [string]$Level = 'INFO'
    )
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$stamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

function Stop-WithError {
    param([string]$Message)
    Write-Log $Message 'ERROR'
    Write-Log "Installation aborted. See log: $LogFile" 'ERROR'
    exit 1
}

# --- Begin -----------------------------------------------------------------
Write-Log "=== Claude Desktop attended install started ===" 'INFO'
Write-Log "Computer: $env:COMPUTERNAME   User: $env:USERNAME   Log: $LogFile" 'INFO'

# 1. Detect architecture
if (-not $Architecture) {
    $procArch = $env:PROCESSOR_ARCHITECTURE
    switch ($procArch) {
        'AMD64' { $Architecture = 'x64' }
        'ARM64' { $Architecture = 'arm64' }
        'x86'   {
            # 32-bit shell on 64-bit OS: check the native arch
            if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') { $Architecture = 'x64' }
            elseif ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { $Architecture = 'arm64' }
            else { Stop-WithError "32-bit Windows is not supported by Claude Desktop." }
        }
        default { Stop-WithError "Unrecognized processor architecture: $procArch" }
    }
}
Write-Log "Target architecture: $Architecture" 'INFO'

# 2. Enable Virtual Machine Platform (Cowork prerequisite)
$rebootRequired = $false
if ($SkipVmPlatform) {
    Write-Log "Skipping Virtual Machine Platform (per -SkipVmPlatform). Cowork will not function until enabled." 'WARN'
}
else {
    try {
        $vmp = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop
        if ($vmp.State -eq 'Enabled') {
            Write-Log "Virtual Machine Platform already enabled." 'OK'
        }
        else {
            Write-Log "Enabling Virtual Machine Platform (required for Cowork)..." 'INFO'
            $result = Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart -ErrorAction Stop
            if ($result.RestartNeeded) {
                $rebootRequired = $true
                Write-Log "Virtual Machine Platform enabled. A RESTART is required before Cowork will work." 'WARN'
            }
            else {
                Write-Log "Virtual Machine Platform enabled." 'OK'
            }
        }
    }
    catch {
        Write-Log "Could not enable Virtual Machine Platform: $($_.Exception.Message)" 'WARN'
        Write-Log "Continuing with install; enable the feature manually if Cowork is needed." 'WARN'
    }
}

# 3. Acquire the MSIX package
$downloadedTemp = $null
if ($MsixPath) {
    if (-not (Test-Path $MsixPath)) { Stop-WithError "MsixPath not found: $MsixPath" }
    $package = (Resolve-Path $MsixPath).Path
    Write-Log "Using local package: $package" 'INFO'
}
else {
    $url = $DownloadUrls[$Architecture]
    $downloadedTemp = Join-Path $env:TEMP ("Claude_{0}_{1:yyyyMMddHHmmss}.msix" -f $Architecture, (Get-Date))
    Write-Log "Downloading latest $Architecture package from: $url" 'INFO'
    try {
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'   # faster Invoke-WebRequest download
        Invoke-WebRequest -Uri $url -OutFile $downloadedTemp -UseBasicParsing -ErrorAction Stop
        $ProgressPreference = $oldProgress
    }
    catch {
        Stop-WithError "Download failed: $($_.Exception.Message). On locked-down networks, pre-download the MSIX and pass -MsixPath."
    }
    $package = $downloadedTemp
    $sizeMB = [math]::Round((Get-Item $package).Length / 1MB, 1)
    Write-Log "Downloaded package ($sizeMB MB): $package" 'OK'
}

# 4. Provision machine-wide (all users)
Write-Log "Provisioning Claude Desktop machine-wide for all users..." 'INFO'
try {
    Add-AppxProvisionedPackage -Online -PackagePath $package -SkipLicense -Regions 'all' -ErrorAction Stop | Out-Null
    Write-Log "Provisioning command completed." 'OK'
}
catch {
    Stop-WithError "Provisioning failed: $($_.Exception.Message). If blocked by AppLocker, allow MSIX packages or add Claude Desktop to the allow list."
}

# 5. Verify
Write-Log "Verifying installation..." 'INFO'
$provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $PackageNameMatch }
if ($provisioned) {
    foreach ($p in $provisioned) {
        Write-Log "Provisioned: $($p.DisplayName) v$($p.Version)" 'OK'
    }
}
else {
    Write-Log "Could not confirm a provisioned 'Claude' package. Review the log and Get-AppxProvisionedPackage output." 'WARN'
}

# 6. Cleanup temp download
if ($downloadedTemp -and (Test-Path $downloadedTemp)) {
    try { Remove-Item $downloadedTemp -Force; Write-Log "Removed temporary download." 'INFO' }
    catch { Write-Log "Could not remove temp file: $downloadedTemp" 'WARN' }
}

# --- Summary ---------------------------------------------------------------
Write-Log "=== Install finished ===" 'OK'
Write-Log "Next: have the user launch Claude (Start menu) and sign in with their work account." 'INFO'
if ($rebootRequired) {
    Write-Log "ACTION REQUIRED: Restart this PC before Cowork will function." 'WARN'
    Write-Host ""
    Write-Host "A RESTART is required to finish enabling Cowork." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Done. Log saved to: $LogFile" -ForegroundColor Green
exit 0
