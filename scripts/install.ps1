param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "config.json not found. Copy config.example.json and edit it first."
}

$programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\proxy-switcher'
$shortcuts = @(
    @{ Name = 'Proxy Switcher.lnk'; Target = Join-Path $root 'switcher.bat'; WorkDir = $root },
    @{ Name = 'OpenCode (proxy-switcher).lnk'; Target = Join-Path $root 'launchers\opencode-launch.bat'; WorkDir = $root },
    @{ Name = 'Antigravity (proxy-switcher).lnk'; Target = Join-Path $root 'launchers\antigravity-launch.bat'; WorkDir = $root }
)

if ($WhatIf) {
    $shortcuts | ForEach-Object { "Would create: $(Join-Path $programs $_.Name) -> $($_.Target)" }
    exit 0
}

New-Item -ItemType Directory -Path $programs -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
foreach ($item in $shortcuts) {
    $link = $shell.CreateShortcut((Join-Path $programs $item.Name))
    $link.TargetPath = $item.Target
    $link.WorkingDirectory = $item.WorkDir
    $link.Save()
    Write-Host "Created: $($item.Name)"
}

Write-Host "Installation complete. Firewall rules remain a separate, administrator-only step."
