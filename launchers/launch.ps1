# ============================================================
# proxy-switcher - unified launcher
# Reads config.json + marker file, injects proxy env vars when
# the marker exists, then launches the requested app.
#
# Usage:
#   pwsh -File launch.ps1 -App opencode -Mode desktop
#   pwsh -File launch.ps1 -App antigravity -Mode cli
#
# Design notes:
#   * opencode desktop: Electron shell, but its core traffic goes
#     through a bundled Node service that honors HTTPS_PROXY.
#   * Antigravity desktop: Electron UI only loads a LOCAL page
#     (https://127.0.0.1:<port>) served by language_server.exe.
#     Do NOT pass --proxy-server here - it hijacks the local
#     loopback request and white-screens the UI. The
#     language_server subprocess (a Go binary) honors the
#     HTTPS_PROXY env vars we set below.
#     We ALSO set NO_PROXY=127.0.0.1,localhost so the Electron UI's
#     local page is fetched directly. Injecting HTTPS_PROXY alone makes
#     Chromium route even loopback requests through the proxy, which
#     white-screens the UI when the proxy is down and can export
#     loopback traffic off-host. The subprocess still uses HTTPS_PROXY.
#   * Electron is single-instance: a second start forwards to the old
#     process and exits. If an instance is already running, quit it and
#     wait so the new process actually inherits the env for this marker.
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('opencode', 'antigravity')]
    [string]$App,

    [Parameter(Mandatory = $true)]
    [ValidateSet('desktop', 'cli')]
    [string]$Mode,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir '..\scripts\ProxySwitcher.ps1')

$cfg = Get-ProxySwitcherConfig
$appCfg = $cfg.apps.$App
$marker = Get-ProxySwitcherMarkerPath -App $App

function Get-DesktopMainProcessId {
    param([string]$ExePath)
    $full = [System.IO.Path]::GetFullPath($ExePath)
    Get-CimInstance -ClassName Win32_Process |
        Where-Object {
            $_.ExecutablePath -and
            [string]::Equals($_.ExecutablePath, $full, [System.StringComparison]::OrdinalIgnoreCase) -and
            $_.CommandLine -and
            ($_.CommandLine -notmatch '--type=')
        } |
        Select-Object -ExpandProperty ProcessId
}

function Stop-DesktopInstance {
    param([string]$ExePath)
    $ids = @(Get-DesktopMainProcessId -ExePath $ExePath)
    if ($ids.Count -eq 0) { return }
    Write-Host "Stopping running instance so the new env takes effect..."
    foreach ($id in $ids) {
        $gp = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($gp) { $null = $gp.CloseMainWindow() }
    }
    $waited = 0
    while ($waited -lt 12) {
        if (@(Get-DesktopMainProcessId -ExePath $ExePath).Count -eq 0) { return }
        Start-Sleep -Seconds 1
        $waited++
    }
    Write-Host "Old instance did not exit in time, forcing stop..."
    foreach ($id in @(Get-DesktopMainProcessId -ExePath $ExePath)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
}

switch ($Mode) {
    'desktop' {
        if (-not (Test-Path -LiteralPath $appCfg.desktop)) {
            Write-Host "Desktop executable not found: $($appCfg.desktop)" -ForegroundColor Red
            exit 1
        }
        Stop-DesktopInstance -ExePath $appCfg.desktop
        $mode = if (Test-Path -LiteralPath $marker) { 'inject' } else { 'clear' }
        if ($mode -eq 'inject') {
            Write-Host "Marker on, launching with proxy: $($cfg.proxy.url)"
        }
        else {
            Write-Host "Marker off, launching direct (no proxy env)."
        }
        Invoke-WithProxySwitcherEnv -Mode $mode -Action {
            param($Desktop)
            Start-Process -FilePath $Desktop
        } -ArgumentList $appCfg.desktop
    }
    'cli' {
        $cli = Resolve-ProxySwitcherCli -App $App
        Invoke-ProxySwitcherCommand -App $App -CommandPath $cli @CommandArgs
    }
}
