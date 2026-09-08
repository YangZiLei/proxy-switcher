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
# Ports that commonly serve an HTTP proxy on loopback, most likely first.
# (Clash Verge Rev mixed 7897 / classic Clash mixed 7890 / FastLink 7892 /
#  Clash HTTP 7899 / v2rayN HTTP 10809 / NekoRay 2080-2081 / generic 8080 …).
# Pure-SOCKS ports (7891/7898/10808/1080) are deliberately excluded: an
# http:// URL pointed at a SOCKS-only listener breaks worse than direct.
$script:ProxySwitcherDefaultProbePorts = @(7897, 7890, 7892, 7893, 7899, 7895, 10809, 2080, 2081, 8080, 20171, 20172)
$script:ProxySwitcherProbeTimeoutMs = 250
$script:ProxySwitcherHttpProbeTimeoutMs = 600

function Test-ProxySwitcherTcpReachable {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = $script:ProxySwitcherProbeTimeoutMs
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($iar)
        return $true
    }
    catch { return $false }
    finally { $client.Close() }
}

# True only when the endpoint is a real HTTP proxy: send a CONNECT tunnel
# request (as a client would for HTTPS) and require an "HTTP/x.y 2xx" reply.
# Rejects SOCKS-only listeners (silent) and HTTP API servers like the clash
# external controller (answers but not with 2xx) — injecting http:// into
# either breaks the tools.
function Test-ProxySwitcherHttpCapable {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$ConnectTimeoutMs = $script:ProxySwitcherProbeTimeoutMs,
        [int]$ReplyTimeoutMs = $script:ProxySwitcherHttpProbeTimeoutMs
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($ConnectTimeoutMs)) { return $false }
        $client.EndConnect($iar)
        $stream = $client.GetStream()
        $stream.ReadTimeout = $ReplyTimeoutMs
        $stream.WriteTimeout = $ReplyTimeoutMs
        $req = [System.Text.Encoding]::ASCII.GetBytes("CONNECT example.com:443 HTTP/1.0`r`nHost: example.com:443`r`n`r`n")
        $stream.Write($req, 0, $req.Length)
        $buf = New-Object byte[] 64
        $n = 0
        while ($n -lt 12) {
            $read = $stream.Read($buf, $n, $buf.Length - $n)
            if ($read -le 0) { break }
            $n += $read
        }
        if ($n -lt 12) { return $false }
        $head = [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
        return ($head -match '^HTTP/\d(\.\d)?\s+2\d\d')
    }
    catch { return $false }
    finally { $client.Close() }
}

function Split-ProxySwitcherUrl {
    param([Parameter(Mandatory = $true)][string]$Url)
    try {
        $u = [Uri]$Url
        if ($u.Host) { return [pscustomobject]@{ Host = $u.Host; Port = $u.Port } }
    }
    catch { }
    return $null
}

function Test-ProxySwitcherUrlReachable {
    param([Parameter(Mandatory = $true)][string]$Url)
    $parts = Split-ProxySwitcherUrl -Url $Url
    if (-not $parts) { return $false }
    Test-ProxySwitcherHttpCapable -HostName $parts.Host -Port $parts.Port
}

# Read the OS-level (system) proxy, e.g. set by Clash "系统代理" / v2rayN /
# FastLink. Returns "http://host:port" or "" when disabled / unparsable.
function Get-ProxySwitcherSystemProxy {
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $prop = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
        if ($prop.ProxyEnable -ne 1) { return '' }
        $raw = [string]$prop.ProxyServer
        if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
        # Formats: "127.0.0.1:7897" or "http=127.0.0.1:7897;https=...;socks=..."
        if ($raw -notmatch '=') {
            $hp = $raw.Trim()
            if ($hp -match '^[^:]+:\d+$') { return "http://$hp" }
            return ''
        }
        foreach ($proto in @('https', 'http')) {
            $m = [regex]::Match($raw, "(?:^|;)\s*$proto\s*=\s*([^;]+)")
            if ($m.Success) {
                $hp = $m.Groups[1].Value.Trim()
                if ($hp -match '^[^:]+:\d+$') { return "http://$hp" }
            }
        }
        return ''
    }
    catch { return '' }
}

# Ordered, de-duplicated candidate list: config url -> system proxy ->
# config candidates -> built-in common ports. Each item: Url + Source.
function Get-ProxySwitcherCandidateUrls {
    $cfg = Get-ProxySwitcherConfig
    # List<T> (not @()) on purpose: $add runs in a child scope where += would
    # only rebind a local copy and the caller would get an empty list.
    $out = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    $add = {
        param($Url, $Source)
        if ([string]::IsNullOrWhiteSpace($Url)) { return }
        $u = $Url.Trim()
        if ($seen.ContainsKey($u)) { return }
        $seen[$u] = $true
        $out.Add([pscustomobject]@{ Url = $u; Source = $Source })
    }
    & $add $cfg.proxy.url 'config'
    & $add (Get-ProxySwitcherSystemProxy) 'system'
    foreach ($c in @($cfg.proxy.candidates)) { & $add ([string]$c) 'config-candidates' }
    foreach ($p in @($cfg.proxy.candidate_ports)) {
        if ("$p" -match '^\d+$') { & $add ("http://127.0.0.1:$p") 'config-ports' }
    }
    foreach ($p in $script:ProxySwitcherDefaultProbePorts) { & $add ("http://127.0.0.1:$p") 'probe' }
    return $out
}

function Get-ProxySwitcherAutoDetectEnabled {
    try {
        $cfg = Get-ProxySwitcherConfig
        if ($null -eq $cfg.proxy.auto_detect) { return $true }
        return [bool]$cfg.proxy.auto_detect
    }
    catch { return $true }
}

# Pick the proxy URL to inject: first reachable candidate (config wins when
# it is alive, otherwise system/probed). Falls back to config url untouched
# when auto_detect is off or nothing responds.
function Resolve-ProxySwitcherUrl {
    $cfg = Get-ProxySwitcherConfig
    $fallback = [pscustomobject]@{ Url = $cfg.proxy.url; Source = 'config'; Reachable = $false }
    if (-not (Get-ProxySwitcherAutoDetectEnabled)) { return $fallback }
    foreach ($c in Get-ProxySwitcherCandidateUrls) {
        if (Test-ProxySwitcherUrlReachable -Url $c.Url) {
            return [pscustomobject]@{ Url = $c.Url; Source = $c.Source; Reachable = $true }
        }
    }
    return $fallback
}

# All reachable candidates, for the interactive picker menu.
function Find-ProxySwitcherAvailable {
    $found = @()
    foreach ($c in Get-ProxySwitcherCandidateUrls) {
        if (Test-ProxySwitcherUrlReachable -Url $c.Url) {
            $found += $c
        }
    }
    return $found
}

# Effective URL for an app: a marker written by an earlier "enable" keeps its
# pinned URL while that endpoint still answers; otherwise re-resolve so a
# swapped proxy app (new port) is picked up without editing config.json.
function Get-ProxySwitcherEffectiveProxyUrl {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('opencode', 'antigravity')]
        [string]$App
    )
    $cfg = Get-ProxySwitcherConfig
    $marker = Get-ProxySwitcherMarkerPath -App $App
    if (Test-Path -LiteralPath $marker) {
        $pinned = ((Get-Content -LiteralPath $marker -Raw -ErrorAction SilentlyContinue) | Out-String).Trim()
        if ($pinned -match '^https?://' -and (Test-ProxySwitcherUrlReachable -Url $pinned)) {
            return [pscustomobject]@{ Url = $pinned; Source = 'marker' }
        }
    }
    $r = Resolve-ProxySwitcherUrl
    return [pscustomobject]@{ Url = $r.Url; Source = $r.Source }
}

function Get-ProxySwitcherEnvPairs {
    param([string]$ProxyUrl = '')
    $cfg = Get-ProxySwitcherConfig
    $proxy = if ([string]::IsNullOrWhiteSpace($ProxyUrl)) { $cfg.proxy.url } else { $ProxyUrl }
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
        [object[]]$ArgumentList = @(),
        [string]$ProxyUrl = ''
    )
    $saved = @{}
    foreach ($n in $script:ProxySwitcherEnvNames) {
        $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process')
    }
    try {
        if ($Mode -eq 'inject') {
            foreach ($pair in Get-ProxySwitcherEnvPairs -ProxyUrl $ProxyUrl) {
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
        $eff = Get-ProxySwitcherEffectiveProxyUrl -App $App
        Invoke-WithProxySwitcherEnv -Mode inject -Action $invoke -ArgumentList $CommandPath, $PassedArgs -ProxyUrl $eff.Url
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
