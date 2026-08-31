# ============================================================
# proxy-switcher - shared PowerShell helpers (config + env inject)
# Dot-sourced by switcher.ps1, launchers/launch.ps1, profile/profile-functions.ps1.
# ============================================================

$script:ProxySwitcherRoot = Split-Path -Parent $PSScriptRoot
$script:ProxySwitcherEnvNames = @('HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY', 'NO_PROXY', 'no_proxy')

function Get-ProxySwitcherConfigPath {
    Join-Path $script:ProxySwitcherRoot 'config.json'
}

function Get-ProxySwitcherConfig {
    $path = Get-ProxySwitcherConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "config.json not found. Copy config.example.json to config.json and edit it."
    }
    Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-ProxySwitcherMarkerPath {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('opencode', 'antigravity')]
        [string]$App
    )
    $cfg = Get-ProxySwitcherConfig
    $name = $cfg.markers.$App
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "config.json missing markers.$App"
    }
    Join-Path $env:USERPROFILE $name
}

# PowerShell hashtables are case-insensitive, so NO_PROXY/no_proxy cannot
# share one @{ }. Use name/value pairs; both names are still applied.
function Get-ProxySwitcherEnvPairs {
    $cfg = Get-ProxySwitcherConfig
    $proxy = $cfg.proxy.url
    $noProxy = if ($cfg.no_proxy) { $cfg.no_proxy } else { '127.0.0.1,localhost' }
    @(
        [pscustomobject]@{ Name = 'HTTPS_PROXY'; Value = $proxy }
        [pscustomobject]@{ Name = 'HTTP_PROXY';  Value = $proxy }
        [pscustomobject]@{ Name = 'ALL_PROXY';   Value = $proxy }
        [pscustomobject]@{ Name = 'NO_PROXY';    Value = $noProxy }
        [pscustomobject]@{ Name = 'no_proxy';    Value = $noProxy }
    )
}

function Invoke-WithProxySwitcherEnv {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('inject', 'clear')]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        [object[]]$ArgumentList = @()
    )
    $saved = @{}
    foreach ($n in $script:ProxySwitcherEnvNames) {
        $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process')
    }
    try {
        if ($Mode -eq 'inject') {
            foreach ($pair in Get-ProxySwitcherEnvPairs) {
                [Environment]::SetEnvironmentVariable($pair.Name, $pair.Value, 'Process')
            }
        }
        else {
            foreach ($n in $script:ProxySwitcherEnvNames) {
                [Environment]::SetEnvironmentVariable($n, $null, 'Process')
            }
        }
        & $Action @ArgumentList
    }
    finally {
        foreach ($n in $script:ProxySwitcherEnvNames) {
            [Environment]::SetEnvironmentVariable($n, $saved[$n], 'Process')
        }
    }
}

function Invoke-ProxySwitcherCommand {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('opencode', 'antigravity')]
        [string]$App,
        [Parameter(Mandatory = $true)]
        [string]$CommandPath,
        [Parameter(ValueFromRemainingArguments = $true)]$PassedArgs
    )
    $marker = Get-ProxySwitcherMarkerPath -App $App
    if ($null -eq $PassedArgs) { $PassedArgs = @() }
    $invoke = {
        param($Path, $CmdArgs)
        & $Path @CmdArgs
    }
    if (Test-Path -LiteralPath $marker) {
        Invoke-WithProxySwitcherEnv -Mode inject -Action $invoke -ArgumentList $CommandPath, $PassedArgs
    }
    else {
        & $invoke $CommandPath $PassedArgs
    }
}

function Resolve-ProxySwitcherCli {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('opencode', 'antigravity')]
        [string]$App
    )
    $cfg = Get-ProxySwitcherConfig
    $cli = $cfg.apps.$App.cli
    if ([string]::IsNullOrWhiteSpace($cli)) {
        throw "config.json missing apps.$App.cli"
    }
    if ($cli -match '[\\/]') {
        if (Test-Path -LiteralPath $cli) {
            return (Resolve-Path -LiteralPath $cli).Path
        }
        throw "CLI not found: $cli"
    }
    $real = Get-Command $cli -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -ne 'Function' } |
        Select-Object -First 1
    if (-not $real) {
        throw "Could not find the real $cli executable/script in PATH."
    }
    $real.Source
}
