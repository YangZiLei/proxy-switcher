# ============================================================
# proxy-switcher - 主菜单
# opencode / Antigravity (agy) 按工具独立代理开关
#
# 原理：
#   每个工具在 %USERPROFILE% 下有一个标记文件（见 config.json）。
#   开启=写标记文件；关闭=删除标记文件。启动器在启动时读取标记，
#   只向进程环境注入 HTTPS_PROXY/HTTP_PROXY/ALL_PROXY——不触碰全局/用户级变量。
#
# 操作流程（两步骤）：
#   第一步：1/2/3/4 设置对应工具的代理状态（写/删标记文件）
#   第二步：按所选工具进入启动菜单，5/6 启动桌面端（按标记注入），
#           7/8 开启代理并启动 CLI（本窗口）
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

$proxy     = $cfg.proxy.url
$markerOc  = Get-ProxySwitcherMarkerPath -App opencode
$markerAgy = Get-ProxySwitcherMarkerPath -App antigravity

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
    Set-Content -LiteralPath $MarkerPath -Value $proxy
    try {
        $cli = Resolve-ProxySwitcherCli -App $App
        Invoke-ProxySwitcherCommand -App $App -CommandPath $cli
    }
    catch {
        Write-Host $_ -ForegroundColor Red
    }
}

# ---- 第一步：设置代理状态 ---------------------------------
function Show-Step1 {
    try { Clear-Host } catch { }
    Write-Host "================================================"
    Write-Host "  AI Agent 代理切换器 (Windows)"
    Write-Host "   (opencode / Antigravity 按工具独立控制)"
    Write-Host "   代理: $proxy"
    Write-Host "================================================"
    Write-StatusLine
    Write-Host ""
    Write-Host "  第一步 - 设置代理状态:"
    Write-Host "  [1] 开启 opencode 代理 (CLI + 桌面)"
    Write-Host "  [2] 开启 antigravity 代理 (CLI + 桌面)"
    Write-Host "  [3] 关闭 opencode 代理 (直连)"
    Write-Host "  [4] 关闭 antigravity 代理 (直连)"
    Write-Host "  [9] 退出"
}

# ---- 第二步：启动（对应工具） -----------------------------
function Show-Step2 {
    param(
        [ValidateSet('opencode', 'antigravity')][string]$App,
        [string]$MarkerPath
    )
    $display = if ($App -eq 'opencode') { 'opencode' } else { 'Antigravity' }
    $state   = if (Test-Path -LiteralPath $MarkerPath) { '开 (走代理)' } else { '关 (直连)' }
    $desktopKey = if ($App -eq 'opencode') { '5' } else { '6' }
    $cliKey     = if ($App -eq 'opencode') { '7' } else { '8' }
    try { Clear-Host } catch { }
    Write-Host "================================================"
    Write-Host "  第二步 - 启动 $display  (当前: $state)"
    Write-Host "   (代理: $proxy)"
    Write-Host "================================================"
    Write-Host ""
    Write-Host "  [$desktopKey] 启动 $display 桌面端 (按标记注入代理)"
    Write-Host "  [$cliKey] 开启代理并启动 $display CLI (本窗口)"
    Write-Host "  [0] 返回第一步"
    Write-Host "  [9] 退出"
}

function Enter-Step2 {
    param(
        [ValidateSet('opencode', 'antigravity')][string]$App,
        [string]$MarkerPath
    )
    $display = if ($App -eq 'opencode') { 'opencode' } else { 'Antigravity' }
    $desktopKey = if ($App -eq 'opencode') { '5' } else { '6' }
    $cliKey     = if ($App -eq 'opencode') { '7' } else { '8' }
    while ($true) {
        Show-Step2 -App $App -MarkerPath $MarkerPath
        $choice = Read-Host "请选择"
        switch ($choice) {
            $desktopKey {
                Write-Host ""
                Write-Host "正在启动 $display 桌面端（按标记注入代理）..."
                Write-Host ""
                Invoke-DesktopLauncher -App $App
                Write-Host ""
                Read-Host "按回车返回"
            }
            $cliKey {
                Write-Host ""
                Write-Host "正在以代理模式启动 $display CLI（退出后返回）..."
                Write-Host ""
                Invoke-CliInWindow -App $App -MarkerPath $MarkerPath
                Write-Host ""
                Read-Host "$display CLI 已退出。按回车返回"
            }
            "0" { return }
            "9" { exit }
            default { Write-Host "无效选项"; Start-Sleep -Seconds 1 }
        }
    }
}

# ============================================================
while ($true) {
    Show-Step1
    $choice = Read-Host "请选择"
    switch ($choice) {
        "1" {
            Set-Content -LiteralPath $markerOc -Value $proxy
            Write-Host ""
            Write-Host "[OK] opencode 代理已开启 (CLI + 桌面)"
            Write-Host "     新终端里运行 'opencode-proxy' 将走代理"
            Read-Host "按回车进入启动菜单"
            Enter-Step2 -App opencode -MarkerPath $markerOc
        }
        "2" {
            Set-Content -LiteralPath $markerAgy -Value $proxy
            Write-Host ""
            Write-Host "[OK] antigravity 代理已开启 (CLI + 桌面)"
            Write-Host "     新终端里运行 'agy-proxy' 将走代理"
            Read-Host "按回车进入启动菜单"
            Enter-Step2 -App antigravity -MarkerPath $markerAgy
        }
        "3" {
            Remove-Item -LiteralPath $markerOc -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "[OK] opencode 已恢复直连"
            Read-Host "按回车进入启动菜单"
            Enter-Step2 -App opencode -MarkerPath $markerOc
        }
        "4" {
            Remove-Item -LiteralPath $markerAgy -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "[OK] antigravity 已恢复直连"
            Read-Host "按回车进入启动菜单"
            Enter-Step2 -App antigravity -MarkerPath $markerAgy
        }
        "9" { exit }
        default { Write-Host "无效选项"; Start-Sleep -Seconds 1 }
    }
}