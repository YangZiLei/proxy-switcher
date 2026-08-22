# ============================================================
# proxy-switcher - main menu
# Per-tool proxy toggle for opencode / Antigravity (agy)
#
# How it works:
#   Each tool has a marker file under %USERPROFILE% (see config.json).
#   Enabling writes the marker; disabling deletes it. Launchers read
#   the marker at startup and inject HTTPS_PROXY/HTTP_PROXY into the
#   process environment only - no global/user-level variables touched.
#
# Usage:
#   Copy config.example.json -> config.json and edit paths.
#   Run switcher.bat (double-click) or: pwsh -File switcher.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

# ---- config -------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "config.json not found. Copy config.example.json to config.json and edit it." -ForegroundColor Red
    exit 1
}
$cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$proxy   = $cfg.proxy.url
$noProxy = if ($cfg.no_proxy) { $cfg.no_proxy } else { '127.0.0.1,localhost' }
$ocApp   = $cfg.apps.opencode
$agyApp  = $cfg.apps.antigravity
$markerOc  = Join-Path $env:USERPROFILE $cfg.markers.opencode
$markerAgy = Join-Path $env:USERPROFILE $cfg.markers.antigravity

function Test-ToolPath([string]$Path) {
    if ($Path -like 'http*' -or $Path -notmatch '\\') { return $true } # remote or bare command
    return Test-Path -LiteralPath $Path
}

# ---- helpers -------------------------------------------------
function Write-StatusLine {
    $oc = if (Test-Path $markerOc) { 'ON (proxy)' } else { 'OFF (direct)' }
    $agy = if (Test-Path $markerAgy) { 'ON (proxy)' } else { 'OFF (direct)' }
    Write-Host "  opencode   : $oc"
    Write-Host "  antigravity: $agy"
}

function Set-ProxyEnv {
    $env:HTTPS_PROXY = $proxy
    $env:HTTP_PROXY  = $proxy
    # Exempt loopback: options 5/7 Start-Process the Electron desktop,
    # which loads a LOCAL page (https://127.0.0.1:<port>). Without NO_PROXY,
    # Chromium routes that local request through the proxy -> white screen.
    $env:NO_PROXY = $noProxy
    $env:no_proxy = $noProxy
}

# ============================================================
while ($true) {
    try { Clear-Host } catch { }
    Write-Host "================================================"
    Write-Host "   AI Agent Proxy Switcher"
    Write-Host "   (opencode / Antigravity, per-tool control)"
    Write-Host "================================================"
    Write-StatusLine
    Write-Host ""
    Write-Host "  [1] Enable  proxy for opencode (CLI + Desktop)"
    Write-Host "  [2] Enable  proxy for antigravity (CLI + Desktop)"
    Write-Host "  [3] Disable proxy for opencode (direct)"
    Write-Host "  [4] Disable proxy for antigravity (direct)"
    Write-Host "  [5] Enable & launch opencode Desktop"
    Write-Host "  [6] Enable & launch opencode CLI (this window)"
    Write-Host "  [7] Enable & launch Antigravity Desktop"
    Write-Host "  [8] Enable & launch Antigravity CLI (this window)"
    Write-Host "  [9] Exit"
    $choice = Read-Host "Select an option"
    switch ($choice) {
        "1" {
            Set-Content -LiteralPath $markerOc -Value $proxy
            Write-Host ""
            Write-Host "[OK] opencode proxy enabled (CLI + Desktop)"
            Write-Host "     New terminals running 'opencode' will use the proxy"
            Read-Host "Press Enter to return"
        }
        "2" {
            Set-Content -LiteralPath $markerAgy -Value $proxy
            Write-Host ""
            Write-Host "[OK] antigravity proxy enabled (CLI + Desktop)"
            Write-Host "     New terminals running 'agy' will use the proxy"
            Read-Host "Press Enter to return"
        }
        "3" {
            Remove-Item -LiteralPath $markerOc -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "[OK] opencode back to direct"
            Read-Host "Press Enter to return"
        }
        "4" {
            Remove-Item -LiteralPath $markerAgy -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "[OK] antigravity back to direct"
            Read-Host "Press Enter to return"
        }
        "5" {
            Set-Content -LiteralPath $markerOc -Value $proxy
            Set-ProxyEnv
            if (-not (Test-ToolPath $ocApp.desktop)) {
                Write-Host "Desktop executable not found: $($ocApp.desktop)" -ForegroundColor Red
                Read-Host "Press Enter to return"
                break
            }
            Write-Host ""
            Write-Host "Launching opencode Desktop with proxy..."
            Start-Process -FilePath $ocApp.desktop
            Read-Host "Launched. Press Enter to return"
        }
        "6" {
            Set-Content -LiteralPath $markerOc -Value $proxy
            Set-ProxyEnv
            Write-Host ""
            Write-Host "Launching opencode CLI with proxy (exit to return)..."
            Write-Host ""
            & $ocApp.cli
            Write-Host ""
            Read-Host "opencode CLI exited. Press Enter to return"
        }
        "7" {
            Set-Content -LiteralPath $markerAgy -Value $proxy
            Set-ProxyEnv
            if (-not (Test-ToolPath $agyApp.desktop)) {
                Write-Host "Desktop executable not found: $($agyApp.desktop)" -ForegroundColor Red
                Read-Host "Press Enter to return"
                break
            }
            Write-Host ""
            Write-Host "Launching Antigravity Desktop with proxy..."
            Start-Process -FilePath $agyApp.desktop
            Read-Host "Launched. Press Enter to return"
        }
        "8" {
            Set-Content -LiteralPath $markerAgy -Value $proxy
            Set-ProxyEnv
            Write-Host ""
            Write-Host "Launching Antigravity CLI with proxy (exit to return)..."
            Write-Host ""
            & $agyApp.cli
            Write-Host ""
            Read-Host "agy CLI exited. Press Enter to return"
        }
        "9" { exit }
        default { Write-Host "Invalid option"; Start-Sleep -Seconds 1 }
    }
}
