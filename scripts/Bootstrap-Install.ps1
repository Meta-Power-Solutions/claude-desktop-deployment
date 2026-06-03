<#
.SYNOPSIS
    Bootstrap: pull the Claude Desktop installer from the public GitHub repo and run it.

.DESCRIPTION
    Short launcher for technicians. Runs prerequisite checks, downloads the latest
    Install-ClaudeDesktop.ps1 from the public repo over HTTPS (no Git, no GitHub CLI,
    no token), and runs it locally. Any extra parameters are forwarded to the installer.

    Repo (public): https://github.com/Meta-Power-Solutions/claude-desktop-deployment

    Run elevated (the installer requires administrator rights). Bootstrap-Install.cmd
    self-elevates for you.

.PARAMETER Ref
    Branch, tag, or commit to pull from. Default: main.

.PARAMETER WorkDir
    Folder to download into and log to. Default: %ProgramData%\ClaudeDeploy.

.PARAMETER SkipPrereqCheck
    Skip the PowerShell/TLS/network checks (use only if a check gives a false negative).

.PARAMETER InstallArgs
    Remaining arguments are passed through to Install-ClaudeDesktop.ps1
    (e.g. -SkipVmPlatform, -Architecture arm64, -MsixPath C:\Deploy\Claude.msix).

.EXAMPLE
    # Default: pull latest from main and install machine-wide:
    powershell -ExecutionPolicy Bypass -File .\Bootstrap-Install.ps1

.EXAMPLE
    # Pull from a release branch and forward an installer option:
    .\Bootstrap-Install.ps1 -Ref release -SkipVmPlatform

.NOTES
    Reference: https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows
#>

[CmdletBinding()]
param(
    [string]$Ref = 'main',
    [string]$WorkDir = (Join-Path $env:ProgramData 'ClaudeDeploy'),
    [switch]$SkipPrereqCheck,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$InstallArgs
)

$ErrorActionPreference = 'Stop'

# --- Settings --------------------------------------------------------------
$Owner      = 'Meta-Power-Solutions'
$Repo       = 'claude-desktop-deployment'
$ScriptPath = 'scripts/Install-ClaudeDesktop.ps1'
$RawUrl     = "https://raw.githubusercontent.com/$Owner/$Repo/$Ref/$ScriptPath"

# Ensure modern TLS on older Windows PowerShell hosts.
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# --- Prerequisite checks ---------------------------------------------------
# No Git or GitHub CLI is required: the installer is pulled over HTTPS using
# PowerShell's built-in web client. These checks confirm the few things that DO
# matter: a recent PowerShell, TLS 1.2, and network reachability.
function Test-Prerequisites {
    param([string[]]$Endpoints)
    $ok = $true

    # 1. PowerShell 5.1 or later
    if ($PSVersionTable.PSVersion.Major -lt 5 -or
        ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        Write-Host "  [FAIL] Windows PowerShell 5.1+ required (found $($PSVersionTable.PSVersion))." -ForegroundColor Red
        $ok = $false
    } else {
        Write-Host "  [ OK ] PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green
    }

    # 2. TLS 1.2 available
    if (([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12) -ne 0) {
        Write-Host "  [ OK ] TLS 1.2 enabled" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] TLS 1.2 could not be enabled on this host." -ForegroundColor Red
        $ok = $false
    }

    # 3. Network reachability (TCP 443) to required endpoints
    foreach ($ep in $Endpoints) {
        $reach = $false
        try {
            $client = New-Object Net.Sockets.TcpClient
            $iar = $client.BeginConnect($ep, 443, $null, $null)
            $reach = $iar.AsyncWaitHandle.WaitOne(5000, $false) -and $client.Connected
            $client.Close()
        } catch { $reach = $false }
        if ($reach) {
            Write-Host "  [ OK ] Reachable: ${ep}:443" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] Cannot reach ${ep}:443 (firewall/proxy?)." -ForegroundColor Red
            $ok = $false
        }
    }
    return $ok
}

if ($SkipPrereqCheck) {
    Write-Host "Skipping prerequisite checks (per -SkipPrereqCheck)." -ForegroundColor Yellow
} else {
    Write-Host "Checking prerequisites..." -ForegroundColor Cyan
    # raw.githubusercontent.com: pull the installer; claude.ai: where the installer
    # then downloads the MSIX.
    $endpoints = @('raw.githubusercontent.com', 'claude.ai')
    if (-not (Test-Prerequisites -Endpoints $endpoints)) {
        Write-Host "ERROR: Prerequisite checks failed. Resolve the items above, or re-run with -SkipPrereqCheck to override." -ForegroundColor Red
        exit 1
    }
}

# --- Prepare working folder -----------------------------------------------
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}
$target = Join-Path $WorkDir 'Install-ClaudeDesktop.ps1'

Write-Host "Pulling installer from GitHub ($Owner/$Repo @ $Ref)..." -ForegroundColor Cyan
Write-Host "  $RawUrl"

# --- Download --------------------------------------------------------------
try {
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $RawUrl -OutFile $target -UseBasicParsing -ErrorAction Stop
    $ProgressPreference = $oldProgress
}
catch {
    Write-Host "ERROR: Could not download the installer from GitHub." -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor R