# ============================================================
# proxy-switcher - Cursor settings.json 同步器
#
# Cursor 桌面端不认 HTTPS_PROXY 环境变量（见 README「Cursor 专属说明」），
# 可靠做法是写 Cursor 用户设置里的 http.proxy + http.proxySupport。
# 本脚本由 switcher.ps1 / launchers/launch.ps1 调用：
#   开代理 -> 写入这两个键；关代理 -> 移除这两个键。
#
# 用法:
#   pwsh -File cursor-settings.ps1 -Action set   -Proxy http://127.0.0.1:7892
#   pwsh -File cursor-settings.ps1 -Action clear
#
# 只管理 http.proxy / http.proxySupport 两个键，其余设置原样保留；
# 因需整体序列化，settings.json 内的注释(JSONC)会被丢弃。
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('set', 'clear')]
    [string]$Action,

    [string]$Proxy
)

$ErrorActionPreference = 'Stop'
$settingsPath = Join-Path $env:APPDATA 'Cursor\User\settings.json'

function Get-CursorSettings {
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $null }
    $raw = Get-Content -LiteralPath $settingsPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw.Trim())) { return $null }
    # settings.json 允许 JSONC 注释；解析前去除 // 行注释与 /* */ 块注释
    $stripped = $raw -replace '(?m)//[^\r\n]*$', ''
    $stripped = $stripped -replace '(?s)/\*.*?\*/', ''
    return $stripped | ConvertFrom-Json -AsHashtable
}

function Set-CursorSettings($ht) {
    $dir = Split-Path -Parent $settingsPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ($ht | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

$settings = Get-CursorSettings

if ($Action -eq 'set') {
    if (-not $Proxy) { Write-Error 'set 需要 -Proxy 参数'; exit 1 }
    if ($null -eq $settings) { $settings = [ordered]@{} }
    $settings['http.proxy'] = $Proxy
    $settings['http.proxySupport'] = 'override'
    Set-CursorSettings $settings
    Write-Host "[OK] Cursor settings.json: http.proxy = $Proxy"
}
else {
    if ($null -ne $settings) {
        $settings.Remove('http.proxy')
        $settings.Remove('http.proxySupport')
        Set-CursorSettings $settings
        Write-Host '[OK] Cursor settings.json: 已移除代理配置（直连）'
    }
    else {
        Write-Host '[OK] Cursor settings.json 不存在或为空，无需清理'
    }
}
