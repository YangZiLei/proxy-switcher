# ============================================================
# proxy-switcher - sync repo runtime files to a local deploy dir
#
# The repo is the source of truth for code; the local dir holds your
# personal config.json (never overwritten by this script).
#
# Usage:
#   pwsh -File scripts/sync-local.ps1 -LocalDir 'C:\path\to\local\proxy-switcher'
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$LocalDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $LocalDir)) {
    throw "LocalDir not found: $LocalDir"
}

# Runtime files only — config.json is personal and stays untouched.
$files = @(
    'switcher.ps1',
    'switcher.bat',
    'config.example.json',
    'scripts\ProxySwitcher.ps1',
    'scripts\install.ps1',
    'scripts\validate.ps1',
    'launchers\launch.ps1',
    'profile\profile-functions.ps1'
)

foreach ($rel in $files) {
    $src = Join-Path $root $rel
    $dst = Join-Path $LocalDir $rel
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Warning "missing in repo, skipped: $rel"
        continue
    }
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "synced: $rel"
}

Write-Host "Done. Personal config.json in $LocalDir was left untouched."
