# ============================================================
# proxy-switcher - 主菜单
# opencode / Antigravity (agy) 按工具独立代理开关
#
# 原理：
#   每个工具在 %USERPROFILE% 下有一个标记文件（见 config.json）。
#   开启=写标记文件；关闭=删除标记文件。启动器在启动时读取标记，
#   只向进程环境注入 HTTPS_PROXY/HTTP_PROXY/ALL_PROXY——不触碰全局/用户级变量。
#
# 用法：
#   复制 config.example.json -> config.json 并修改路径。
#   双击 switcher.bat，或：pwsh -File switcher.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

# ---- 配置 -------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'scripts\ProxySwitcher.ps1')

try {
    $cfg = Get-ProxySwitcherConfig
}
catch {
    Write-Host "未找到 config.json。请复制 config.example.json 为 config.json 并修改。" -ForegroundColor Red
    exit 1
}

$proxyCfg   = $cfg.proxy.url
$markerOc  = Get-ProxySwitcherMarkerPath -App opencode
$markerAgy = Get-ProxySwitcherMarkerPath -App antigravity

function Get-ResolvedProxyForMenu {
    try { Resolve-ProxySwitcherUrl }
    catch { [pscustomobject]@{ Url = $proxyCfg; Source = 'config'; Reachable = $false } }
}

function Enable-ProxySwitcherMarker {
    param(
        [ValidateSet('opencode', 'antigravity')][string]$App,
        [string]$MarkerPath
    )
    $r = Get-ResolvedProxyForMenu
    Set-Content -LiteralPath $MarkerPath -Value $r.Url
    if ($r.Reachable) {
        Write-Host ""
        Write-Host "[OK] $App 代理已开启 (CLI + 桌面)"
        Write-Host "     地址: $($r.Url) (来源: $($r.Source))"
    }
    else {
        Write-Host ""
        Write-Host "[WARN] 未探测到可用代理，已按配置写入 $($r.Url)，启动时将直连失败回退。" -ForegroundColor Yellow
        Write-Host "      请确认代理软件已启动，或用 [0] 探测端口后重试。"
    }
}

function Select-ProxySwitcherUrl {
    Write-Host ""
    Write-Host "正在探测本机代理 (配置 > 系统代理 > 常见端口)..."
    $found = @(Find-ProxySwitcherAvailable)
    if ($found.Count -eq 0) {
        Write-Host "[FAIL] 未发现任何可用代理端口。" -ForegroundColor Red
        Write-Host "       请先启动代理软件（Clash / FastLink / v2rayN 等），或确认它监听 127.0.0.1。"
        Read-Host "按回车返回"
        return
    }
    Write-Host "发现以下可用代理："
    for ($i = 0; $i -lt $found.Count; $i++) {
        Write-Host ("  [{0}] {1}  (来源: {2})" -f ($i + 1), $found[$i].Url, $found[$i].Source)
    }
    Write-Host "  [0] 取消"
    $sel = Read-Host "选择要写入 config.json 的地址序号"
    if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $found.Count) {
        $picked = $found[[int]$sel - 1].Url
        $cfgPath = Get-ProxySwitcherConfigPath
        $raw = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
        $raw.proxy.url = $picked
        $raw | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cfgPath -Encoding utf8
        $script:cfg = Get-ProxySwitcherConfig
        Write-Host "[OK] 已将代理地址设为 $picked" -ForegroundColor Green
    }
    else {
        Write-Host "已取消，未修改。"
    }
    Read-Host "按回车返回"
}

$pwshExe = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $pwshExe)) { $pwshExe = Join-Path $PSHOME 'pwsh' }
$launcher = Join-Path $scriptDir 'launchers\launch.ps1'

# ---- 辅助 -------------------------------------------------
function Write-StatusLine {
    $oc  = if (Test-Path $markerOc)  { '开 (走代理)' } else { '关 (直连)' }
    $agy = if (Test-Path $markerAgy) { '开 (走代理)' } else { '关 (直连)' }
    Write-Host "  opencode   : $oc"
    Write-Host "  antigravity: $agy"
}

function Invoke-DesktopLauncher {
    param([ValidateSet('opencode', 'antigravity')][string]$App)
    & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $launcher -App $App -Mode desktop
}

function Invoke-CliInWindow {
    param(
        [ValidateSet('opencode', 'antigravity')][string]$App,
        [string]$MarkerPath
    )
    $r = Get-ResolvedProxyForMenu
    Set-Content -LiteralPath $MarkerPath -Value $r.Url
    Write-Host "     地址: $($r.Url) (来源: $($r.Source))"
    try {
        $cli = Resolve-ProxySwitcherCli -App $App
        Invoke-ProxySwitcherCommand -App $App -CommandPath $cli
    }
    catch {
        Write-Host $_ -ForegroundColor Red
    }
}

# ============================================================
while ($true) {
    try { Clear-Host } catch { }
    $menuProxy = Get-ResolvedProxyForMenu
    Write-Host "================================================"
    Write-Host "  AI Agent 代理切换器 (Windows)"
    Write-Host "   (opencode / Antigravity 按工具独立控制)"
    Write-Host "   代理: $($menuProxy.Url) (来源: $($menuProxy.Source))"
    Write-Host "================================================"
    Write-StatusLine
    Write-Host ""
    Write-Host "  ── opencode ──────────────────────"
    Write-Host "  [1] 开启 代理 (CLI + 桌面)"
    Write-Host "  [3] 关闭 代理 (直连)"
    Write-Host "  [5] 启动 桌面端 (按标记注入代理)"
    Write-Host "  [7] 开启代理并启动 CLI (本窗口)"
    Write-Host ""
    Write-Host "  ── Antigravity ───────────────────"
    Write-Host "  [2] 开启 代理 (CLI + 桌面)"
    Write-Host "  [4] 关闭 代理 (直连)"
    Write-Host "  [6] 启动 桌面端 (按标记注入代理)"
    Write-Host "  [8] 开启代理并启动 CLI (本窗口)"
    Write-Host ""
    Write-Host "  [0] 探测本机代理端口 (换代理软件后用这个)"
    Write-Host ""
    Write-Host "  [9] 退出"
    $choice = Read-Host "请选择"
    switch ($choice) {
        "0" {
            Select-ProxySwitcherUrl
        }
        "1" {
            Enable-ProxySwitcherMarker -App opencode -MarkerPath $markerOc
            Write-Host "     新终端里运行 'opencode-proxy' 将走代理"
            Read-Host "按回车返回"
        }
        "2" {
            Enable-ProxySwitcherMarker -App antigravity -MarkerPath $markerAgy
            Write-Host "     新终端里运行 'agy-proxy' 将走代理"
            Read-Host "按回车返回"
        }
        "3" {
            Remove-Item -LiteralPath $markerOc -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "[OK] opencode 已恢复直连"
            Read-Host "按回车返回"
        }
        "4" {
            Remove-Item -LiteralPath $markerAgy -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "[OK] antigravity 已恢复直连"
            Read-Host "按回车返回"
        }
        "5" {
            Write-Host ""
            Write-Host "正在启动 opencode 桌面端（按标记注入代理）..."
            Write-Host ""
            Invoke-DesktopLauncher -App opencode
            Write-Host ""
            Read-Host "按回车返回"
        }
        "6" {
            Write-Host ""
            Write-Host "正在启动 Antigravity 桌面端（按标记注入代理）..."
            Write-Host ""
            Invoke-DesktopLauncher -App antigravity
            Write-Host ""
            Read-Host "按回车返回"
        }
        "7" {
            Write-Host ""
            Write-Host "正在以代理模式启动 opencode CLI（退出后返回）..."
            Write-Host ""
            Invoke-CliInWindow -App opencode -MarkerPath $markerOc
            Write-Host ""
            Read-Host "opencode CLI 已退出。按回车返回"
        }
        "8" {
            Write-Host ""
            Write-Host "正在以代理模式启动 Antigravity CLI（退出后返回）..."
            Write-Host ""
            Invoke-CliInWindow -App antigravity -MarkerPath $markerAgy
            Write-Host ""
            Read-Host "agy CLI 已退出。按回车返回"
        }
        "9" { exit }
        default { Write-Host "无效选项"; Start-Sleep -Seconds 1 }
    }
}
