# ============================================================
# proxy-switcher - main menu
# Per-tool proxy toggle for opencode / Antigravity (agy) / Cursor
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
$curApp  = $cfg.apps.cursor
$markerOc  = Join-Path $env:USERPROFILE $cfg.markers.opencode
$markerAgy = Join-Path $env:USERPROFILE $cfg.markers.antigravity
$markerCur = if ($cfg.markers.cursor) { Join-Path $env:USERPROFILE $cfg.markers.cursor } else { $null }

function Test-ToolPath([string]$Path) {
    if ($Path -like 'http*' -or $Path -notmatch '\\') { return $true } # remote or bare command
    return Test-Path -LiteralPath $Path
}

# ---- helpers -------------------------------------------------
function Write-StatusLine {
    $oc  = if (Test-Path $markerOc)  { 'ON (proxy)' } else { 'OFF (direct)' }
    $agy = if (Test-Path $markerAgy) { 'ON (proxy)' } else { 'OFF (direct)' }
    $cur = if ($markerCur -and (Test-Path $markerCur)) { 'ON (proxy)' } else { 'OFF (direct)' }
    Write-Host "  opencode   : $oc"
    Write-Host "  antigravity: $agy"
    Write-Host "  cursor     : $cur"
}

function Set-ProxyEnv {
    $env:HTTPS_PROXY = $proxy
    $env:HTTP_PROXY  = $proxy
    # Exempt loopback: options 7/9/11 Start-Process Electron desktops;
    # Chromium would route local requests through the proxy otherwise.
    $env:NO_PROXY = $noProxy
    $env:no_proxy = $noProxy
}

# ============================================================
while ($true) {
    try { Clear-Host } catch { }
    Write-Host "================================================"
    Write-Host "   AI Agent Proxy Switcher"
    Write-Host "   (opencode / Antigravity / Cursor, per-tool)"
    Write-Host "================================================"
    Write-StatusLine
    Write-Host ""
    Write-Host "  --- Enable ---"
    Write-Host "  [1] Enable  proxy for opencode (CLI + Desktop)"
    Write-Host "  [2] Enable  proxy for antigravity (CLI + Desktop)"
    Write-Host "  [3] Enable  proxy for cursor (Desktop)"
    Write-Host "  --- Disable ---"
    Write-Host "  [4] Disable proxy for opencode (direct)"
    Write-Host "  [5] Disable proxy for antigravity (direct)"
    Write-Host "  [6] Disable proxy for cursor (direct)"
    Write-Host "  --- Enable & launch ---"
    Write-Host "  [7]  Enable & launch opencode Desktop"
    Write-Host "  [8]  Enable & launch opencode CLI (this window)"
    Write-Host "  [9]  Enable & launch Antigravity Desktop"
    Write-Host "  [10] Enable & launch Antigravity CLI (this window)"
    Write-Host "  [11] Enable & launch Cursor Desktop"
    Write-Host "  [12] Exit"
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
            Set-Content -LiteralPath $markerCur -Value $proxy
            Write-Host ""
            Write-Host "[OK] cursor proxy enabled (Desktop)"
            Write-Host "     Restart Cursor (via launcher or option 11) to apply"
            Read-Host "Press Enter to return"
        }
        "4" {
            Remove-Item -LiteralPath $markerOc -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "[OK] opencode back to direct"
            Read-Host "Press Enter to return"
        }
        "5" {
            Remove-Item -LiteralPath $markerAgy -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "[OK] antigravity back to direct"
            Read-Host "Press Enter to return"
        }
        "6" {
            Remove-Item -LiteralPath $markerCur -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "[OK] cursor back to direct"
            Read-Host "Press Enter to return"
        }
        "7" {
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
        "8" {
            Set-Content -LiteralPath $markerOc -Value $proxy
            Set-ProxyEnv
            Write-Host ""
            Write-Host "Launching opencode CLI with proxy (exit to return)..."
            Write-Host ""
            & $ocApp.cli
            Write-Host ""
            Read-Host "opencode CLI exited. Press Enter to return"
        }
        "9" {
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
        "10" {
            Set-Content -LiteralPath $markerAgy -Value $proxy
            Set-ProxyEnv
            Write-Host ""
            Write-Host "Launching Antigravity CLI with proxy (exit to return)..."
            Write-Host ""
            & $agyApp.cli
            Write-Host ""
            Read-Host "agy CLI exited. Press Enter to return"
        }
        "11" {
            Set-Content -LiteralPath $markerCur -Value $proxy
            Set-ProxyEnv
            if (-not (Test-ToolPath $curApp.desktop)) {
                Write-Host "Desktop executable not found: $($curApp.desktop)" -ForegroundColor Red
                Read-Host "Press Enter to return"
                break
            }
            Write-Host ""
            Write-Host "Launching Cursor Desktop with proxy..."
            Start-Process -FilePath $curApp.desktop
            Read-Host "Launched. Press Enter to return"
        }
        "12" { exit }
        default { Write-Host "Invalid option"; Start-Sleep -Seconds 1 }
    }
}
