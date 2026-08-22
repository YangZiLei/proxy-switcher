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
$configPath = Join-Path $scriptDir '..\config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "config.json not found. Copy config.example.json to config.json and edit it." -ForegroundColor Red
    exit 1
}
$cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$appCfg = $cfg.apps.$App
$marker = Join-Path $env:USERPROFILE $cfg.markers.$App
$proxy = $cfg.proxy.url
$noProxy = if ($cfg.no_proxy) { $cfg.no_proxy } else { '127.0.0.1,localhost' }

if (Test-Path $marker) {
    $env:HTTPS_PROXY = $proxy
    $env:HTTP_PROXY  = $proxy
    # Exempt loopback so the Electron UI (which loads a LOCAL page at
    # https://127.0.0.1:<port>) does NOT route that local request through
    # the proxy. Without this, a not-yet-ready proxy makes the UI fail with
    # ERR_TIMED_OUT (white screen), and loopback traffic can be exported
    # off-host via the proxy chain. The language_server subprocess still
    # reaches the internet through HTTPS_PROXY as intended.
    $env:NO_PROXY = $noProxy
    $env:no_proxy = $noProxy
}

switch ($Mode) {
    'desktop' {
        if (-not (Test-Path -LiteralPath $appCfg.desktop)) {
            Write-Host "Desktop executable not found: $($appCfg.desktop)" -ForegroundColor Red
            exit 1
        }
        Start-Process -FilePath $appCfg.desktop
    }
    'cli' {
        & $appCfg.cli @CommandArgs
    }
}
