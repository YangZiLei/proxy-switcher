# ============================================================
# proxy-switcher - Windows Firewall fix for Antigravity desktop
#
# Symptom: Antigravity desktop starts but shows a white screen;
# main.log shows "Failed to load URL: https://127.0.0.1:<port>/
# with error: ERR_CONNECTION_TIMED_OUT".
#
# Root cause: Windows Defender Firewall blocks loopback
# connections to Antigravity.exe / language_server.exe. It is
# NOT a proxy issue - verified by the fact that direct curl to
# the local port also times out, regardless of proxy settings.
#
# Fix: create narrowly scoped allow rules for the two executables.
# This script does not change the user's firewall profile state.
#
# Run as Administrator:
#   Right-click -> Run with PowerShell, or:
#   pwsh -File firewall-fix.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir '..\config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "config.json not found at: $configPath" -ForegroundColor Red
    Write-Host "Copy config.example.json to config.json and edit it first."
    Read-Host "Press Enter to exit"
    exit 1
}
$cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$exePath = $cfg.apps.antigravity.desktop
$binDir = Split-Path -Parent $exePath
$lsPath = Join-Path $binDir 'resources\bin\language_server.exe'

if (-not (Test-Path -LiteralPath $exePath)) {
    Write-Host "Antigravity not found at: $exePath" -ForegroundColor Red
    exit 1
}

Write-Host "Creating firewall rules for:"
Write-Host "  $exePath"
if (Test-Path -LiteralPath $lsPath) { Write-Host "  $lsPath" }

$paths = @($exePath)
if (Test-Path -LiteralPath $lsPath) { $paths += $lsPath }

foreach ($p in $paths) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($p)
    $inboundName = "proxy-switcher $name Inbound"
    $outboundName = "proxy-switcher $name Outbound"

    Get-NetFirewallRule -DisplayName $inboundName, $outboundName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    # Antigravity's local UI only needs loopback inbound access.
    # IPv4 loopback only: some Windows builds reject '::1' as LocalAddress
    # with "unspecified broadcast, multicast, or loopback IPv6 address",
    # which aborts the script before any rule is created. The Electron UI
    # loads 127.0.0.1:<port>, so the IPv4 rule is sufficient.
    New-NetFirewallRule -DisplayName $inboundName -Direction Inbound -Action Allow -Program $p `
        -Profile Any -LocalAddress @('127.0.0.1') -RemoteAddress @('127.0.0.1') `
        -ErrorAction Stop | Out-Null

    # The language server still needs outbound access to Google services.
    New-NetFirewallRule -DisplayName $outboundName -Direction Outbound -Action Allow -Program $p `
        -Profile Any -ErrorAction Stop | Out-Null
    Write-Host "  allowed: $p"
}

Write-Host ""
Write-Host "Done. Loopback inbound and outbound application rules created."
Write-Host "Firewall profile settings were not changed."
Read-Host "Press Enter to exit"
