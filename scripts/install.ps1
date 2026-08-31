param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root 'config.json'
$examplePath = Join-Path $root 'config.example.json'

function Copy-ProxySwitcherConfig {
    if (-not (Test-Path -LiteralPath $examplePath)) {
        throw "config.example.json not found at $examplePath"
    }
    $raw = Get-Content -LiteralPath $examplePath -Raw
    $escaped = $env:LOCALAPPDATA.Replace('\', '\\')
    $raw = $raw.Replace('%LOCALAPPDATA%', $escaped)
    Set-Content -LiteralPath $configPath -Value $raw -Encoding utf8
}

$programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\proxy-switcher'
$shortcuts = @(
    @{ Name = 'Proxy Switcher.lnk'; Target = Join-Path $root 'switcher.bat'; WorkDir = $root },
    @{ Name = 'OpenCode (proxy-switcher).lnk'; Target = Join-Path $root 'launchers\opencode-launch.bat'; WorkDir = $root },
    @{ Name = 'Antigravity (proxy-switcher).lnk'; Target = Join-Path $root 'launchers\antigravity-launch.bat'; WorkDir = $root }
)

if ($WhatIf) {
    if (-not (Test-Path -LiteralPath $configPath)) {
        "Would create: $configPath from config.example.json (expand %LOCALAPPDATA%)"
    }
    $shortcuts | ForEach-Object { "Would create: $(Join-Path $programs $_.Name) -> $($_.Target)" }
    exit 0
}

if (-not (Test-Path -LiteralPath $configPath)) {
    Copy-ProxySwitcherConfig
    Write-Host "Generated config.json from example (desktop paths under LOCALAPPDATA). Edit proxy.url if needed."
}
else {
    Write-Host "config.json already exists, skipping."
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
