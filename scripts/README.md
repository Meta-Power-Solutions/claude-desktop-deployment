# Deployment Scripts

Scripts for **attended** (technician-at-the-desktop) installation of Claude Desktop
on Windows. The actual installer lives in this **public** GitHub repo and is pulled
on demand by a small bootstrap, so technicians always run the latest version. The
same MSIX + provisioning approach is reused later for unattended deployment via
Intune / SCCM / Group Policy.

Repo: `https://github.com/Meta-Power-Solutions/claude-desktop-deployment` (public — no token needed)

## Files

| File | Purpose |
| --- | --- |
| `Bootstrap-Install.cmd` | **The only file a technician needs.** Double-clickable launcher. Self-elevates to admin, then pulls `Bootstrap-Install.ps1` from GitHub and runs it. |
| `Bootstrap-Install.ps1` | Runs prerequisite checks, pulls the latest `Install-ClaudeDesktop.ps1` from the public repo, and runs it. Fetched automatically by the `.cmd`. |
| `Install-ClaudeDesktop.ps1` | The installer itself. Enables the Virtual Machine Platform (for Cowork), downloads or uses a local MSIX, and provisions Claude Desktop **machine-wide** for all users. Pulled from GitHub by the bootstrap. |
| `Install-ClaudeDesktop.cmd` | Optional offline launcher: self-elevates and runs `Install-ClaudeDesktop.ps1` directly, without GitHub (use when the whole folder is copied to the machine). |

## Prerequisites

Pulling and running the installer uses **no Git, no GitHub CLI, and no token** — the
repo is public and the bootstrap fetches files over HTTPS using PowerShell's built-in
web client. The requirements are:

| Requirement | Notes |
| --- | --- |
| **Windows PowerShell 5.1+** | Built into Windows 10 (1903+) and Windows 11. The bootstrap checks the version. |
| **TLS 1.2** | The bootstrap enables it at runtime and verifies it. |
| **Administrator rights** | The installer provisions machine-wide and enables a Windows feature. `Bootstrap-Install.cmd` self-elevates (UAC). |
| **HTTPS (443) access** | To `raw.githubusercontent.com` (pull the scripts) and `claude.ai` (download the MSIX). The bootstrap tests reachability to each. |

The bootstrap runs these checks automatically before downloading and stops with a
clear message if any fail. To bypass them (e.g. on a host where the TCP probe is
blocked but HTTPS works), add `-SkipPrereqCheck`.

> If you later switch to cloning the whole repo instead of fetching the one script,
> *then* you'd add Git for Windows or the GitHub CLI as prerequisites. The current
> HTTPS method does not need them.

## Recommended workflow: pull from GitHub

The technician needs only **`Bootstrap-Install.cmd`** — it fetches everything else.

1. Get `Bootstrap-Install.cmd` onto the PC (USB stick, or download from OneDrive/office.com).
2. **Double-click `Bootstrap-Install.cmd`** and approve the UAC prompt.
3. Watch the prerequisite checks (PowerShell, TLS 1.2, network). It then pulls the installer and runs it.
4. If it reports a **restart required**, reboot before testing Cowork.
5. Have the user open **Claude** from the Start menu and sign in with their work account.

> If the `.cmd` was downloaded via a browser (OneDrive/office.com), Windows may show a
> SmartScreen prompt — click **More info → Run anyway** — or clear the flag first with
> right-click → **Properties** → **Unblock**.

### Bootstrap parameters

| Parameter | Description |
| --- | --- |
| `-Ref` | Branch, tag, or commit to pull from. Default: `main`. |
| `-WorkDir` | Download + log folder. Default: `%ProgramData%\ClaudeDeploy`. |
| `-SkipPrereqCheck` | Skip the PowerShell/TLS/network checks (use only if a check gives a false negative). |
| *(extra args)* | Anything else is forwarded to `Install-ClaudeDesktop.ps1` (see below). |

```powershell
# Pull from a release branch and forward an installer option:
.\Bootstrap-Install.ps1 -Ref release -SkipVmPlatform
```

## Offline / no-GitHub workflow

If the machine can't reach GitHub, copy the whole `scripts` folder and run the installer directly:

1. **Double-click `Install-ClaudeDesktop.cmd`** and approve UAC, **or**
2. Open an **elevated** PowerShell window in the folder and run:

```powershell
# Download the latest MSIX and install machine-wide (enables Cowork prereq):
powershell -ExecutionPolicy Bypass -File .\Install-ClaudeDesktop.ps1

# Install from a pre-downloaded package (fully offline):
.\Install-ClaudeDesktop.ps1 -MsixPath "C:\Deploy\Claude.msix"

# Force architecture, or skip the Cowork prerequisite:
.\Install-ClaudeDesktop.ps1 -Architecture arm64
.\Install-ClaudeDesktop.ps1 -SkipVmPlatform
```

### Installer parameters

| Parameter | Description |
| --- | --- |
| `-MsixPath` | Path to a local Claude MSIX. If omitted, the latest is downloaded for the detected architecture. |
| `-Architecture` | `x64` or `arm64`. Default: auto-detect. |
| `-SkipVmPlatform` | Skip enabling Virtual Machine Platform. Cowork will not work until it is enabled. |
| `-LogPath` | Folder for the log file. Default: the script folder (the bootstrap sets this to `%ProgramData%\ClaudeDeploy`). |

## What the installer does

1. Confirms it is running **elevated** (admin).
2. Detects CPU architecture (x64 / arm64).
3. Enables the **Virtual Machine Platform** Windows feature (Cowork prerequisite) unless `-SkipVmPlatform`.
4. Downloads the latest MSIX (or uses `-MsixPath`).
5. Provisions machine-wide: `Add-AppxProvisionedPackage -Online -SkipLicense -Regions all`.
6. Verifies the package and writes a timestamped log (`Install-ClaudeDesktop_YYYYMMDD_HHMMSS.log`).

## Requirements & notes

- Windows 10 (1903+) or Windows 11, x64 or arm64; administrator rights.
- Central deployment and policy controls require a **Team or Enterprise plan**.
- On networks that block downloads, pre-download the MSIX and pass `-MsixPath`.
- If **AppLocker** blocks the package, allow MSIX packages or add Claude Desktop to the allow list.
- Enterprise policy/configuration (auto-update control, allowed Cowork folders, forced org login,
  extension/MCP controls) is **not** set by these scripts — that will live under `config/`.

## Download sources (reference)

- Claude MSIX (x64): `https://claude.ai/api/desktop/win32/x64/msix/latest/redirect`
- Claude MSIX (arm64): `https://claude.ai/api/desktop/win32/arm64/msix/latest/redirect`

Reference: [Deploy Claude Desktop for Windows](https://support.claude.com/en/articles/12622703-deploy-claude-desktop-for-windows)
