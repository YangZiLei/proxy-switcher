# ============================================================
# proxy-switcher - optional PowerShell profile functions
#
# Dot-source this file from your PowerShell profile to add the
# explicit commands `opencode-proxy` and `agy-proxy`.
#
#   Add to $PROFILE:
#     . "C:\path\to\proxy-switcher\profile\profile-functions.ps1"
#
# Why functions instead of PATH wrappers?
#   * Windows resolves .EXE before .BAT for same-named commands,
#     so a same-name bat cannot shadow agy.exe without PATH
#     surgery (fragile).
#   * Explicit names avoid overwriting existing opencode/agy
#     functions, including user plugins and custom profile logic.
# ============================================================

$script:ProxySwitcherConfigPath = Join-Path $PSScriptRoot '..\config.json'

function Read-ProxySwitcherConfig {
    if (-not (Test-Path -LiteralPath $script:ProxySwitcherConfigPath)) {
        throw "proxy-switcher config.json not found at $script:ProxySwitcherConfigPath"
    }
    Get-Content -LiteralPath $script:ProxySwitcherConfigPath -Raw | ConvertFrom-Json
}

function Invoke-WithProxySwitch {
    param(
        [Parameter(Mandatory = $true)][string]$Marker,
        [Parameter(Mandatory = $true)][string]$CommandPath,
        [Parameter(ValueFromRemainingArguments = $true)]$PassedArgs
    )
    $cfg = Read-ProxySwitcherConfig
    $proxy   = $cfg.proxy.url
    $noProxy = if ($cfg.no_proxy) { $cfg.no_proxy } else { '127.0.0.1,localhost' }
    if (Test-Path (Join-Path $env:USERPROFILE $Marker)) {
        # Inject into the child command only. Pre-existing values are saved and
        # restored afterwards, so a proxy the user had already exported in this
        # session survives the wrapper (previously it was deleted); variables
        # that were not set stay unset. finally guarantees restoration even if
        # the command exits non-zero.
        $names = 'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY', 'no_proxy'
        $saved = @{}
        foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }

        $env:HTTPS_PROXY = $proxy
        $env:HTTP_PROXY  = $proxy
        $env:NO_PROXY    = $noProxy
        $env:no_proxy    = $noProxy
        try {
            & $CommandPath @PassedArgs
        }
        finally {
            foreach ($n in $names) {
                # $null value removes the process-level variable.
                [Environment]::SetEnvironmentVariable($n, $saved[$n])
            }
        }
    }
    else {
        & $CommandPath @PassedArgs
    }
}

# agy (Antigravity CLI) - binary lives in %LOCALAPPDATA%\agy\bin\agy.EXE
function agy-proxy {
    $real = Get-Command "$env:LOCALAPPDATA\agy\bin\agy.EXE" -ErrorAction Stop
    Invoke-WithProxySwitch -Marker (Read-ProxySwitcherConfig).markers.antigravity `
        -CommandPath $real.Source @args
}

# opencode - resolve the real executable without replacing `opencode`
function opencode-proxy {
    $real = Get-Command opencode -All |
        Where-Object { $_.CommandType -ne 'Function' } |
        Select-Object -First 1
    if (-not $real) {
        throw 'Could not find the real opencode executable/script in PATH.'
    }
    Invoke-WithProxySwitch -Marker (Read-ProxySwitcherConfig).markers.opencode `
        -CommandPath $real.Source @args
}
