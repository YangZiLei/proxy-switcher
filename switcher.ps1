# ============================================================
# proxy-switcher - 主菜单
# opencode / Antigravity (agy) 按工具独立代理开关
#
# 原理：
#   每个工具在 %USERPROFILE% 下有一个标记文件（见 config.json）。
#   开启=写标记文件；关闭=删除标记文件。启动器在启动时读取标记，
#   只向进程环境注入 HTTPS_PROXY/HTTP_PROXY——不触碰全局/用户级变量。
#
# 用法：
#   复制 config.example.json -> config.json 并修改路径。
#   双击 switcher.bat，或：pwsh -File switcher.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

# ---- 配置 -------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host "未找到 config.json。请复制 config.example.json 为 config.json 并修改。" -ForegroundColor Red
    exit 1
}
$cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$proxy   = $cfg.proxy.url
$noProxy = if ($cfg.no_proxy) { $cfg.no_proxy } else { '127.0.0.1,localhost' }
$ocApp   = $cfg.apps.opencode
$agyApp  = $cfg.apps.antigravity
$markerOc  = Join-Path $env:USERPROFILE $cfg.markers.opencode
$markerAgy = Join-Path $env:USERPROFILE $cfg.markers.antigravity

function Test-ToolPath([string]$Path) {
    if ($Path -like 'http*' -or $Path -notmatch '\\') { return $true } # 远程或裸命令
    return Test-Path -LiteralPath $Path
}

# ---- 辅助 -------------------------------------------------
function Write-StatusLine {
    $oc  = if (Test-Path $markerOc)  { '开 (走代理)' } else { '关 (直连)' }
    $agy = if (Test-Path $markerAgy) { '开 (走代理)' } else { '关 (直连)' }
    Write-Host "  opencode   : $oc"
    Write-Host "  antigravity: $agy"
}

function Set-ProxyEnv {
    $env:HTTPS_PROXY = $proxy
    $env:HTTP_PROXY  = $proxy
    # 豁免回环：选项 5/6 通过 Start-Process 启动 Electron 桌面端，
    # 否则 Chromium 会把本地回环请求也走代理。
    $env:NO_PROXY = $noProxy
    $env:no_proxy = $noProxy
}

# ============================================================
while ($true) {
    try { Clear-Host } catch { }
    Write-Host "================================================"
    Write-Host "   AI Agent 代理切换器 (Windows)"
    Write-Host "   (opencode / Antigravity 按工具独立控制)"
    Write-Host "   代理: $proxy"
    Write-Host "================================================"
    Write-StatusLine
    Write-Host ""
    Write-Host "  [1] 开启 opencode 代理 (CLI + 桌面)"
    Write-Host "  [2] 开启 antigravity 代理 (CLI + 桌面)"
    Write-Host "  [3] 关闭 opencode 代理 (直连)"
    Write-Host "  [4] 关闭 antigravity 代理 (直连)"
    Write-Host "  [5] 启动 opencode 桌面端 (按标记注入代理)"
    Write-Host "  [6] 启动 Antigravity 桌面端 (按标记注入代理)"
    Write-Host "  [7] 开启代理并启动 opencode CLI (本窗口)"
    Write-Host "  [8] 开启代理并启动 Antigravity CLI (本窗口)"
    Write-Host "  [9] 退出"
    $choice = Read-Host "请选择"
    switch ($choice) {
        "1" {
            Set-Content -LiteralPath $markerOc -Value $proxy
            Write-Host ""
            Write-Host "[OK] opencode 代理已开启 (CLI + 桌面)"
            Write-Host "     新终端里运行 'opencode' 将走代理"
            Read-Host "按回车返回"
        }
        "2" {
            Set-Content -LiteralPath $markerAgy -Value $proxy
            Write-Host ""
            Write-Host "[OK] antigravity 代理已开启 (CLI + 桌面)"
            Write-Host "     新终端里运行 'agy' 将走代理"
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
            Set-Content -LiteralPath $markerOc -Value $proxy
            Set-ProxyEnv
            if (-not (Test-ToolPath $ocApp.desktop)) {
                Write-Host "未找到桌面端程序: $($ocApp.desktop)" -ForegroundColor Red
                Read-Host "按回车返回"
                break
            }
            Write-Host ""
            Write-Host "正在以代理模式启动 opencode 桌面端..."
            Start-Process -FilePath $ocApp.desktop
            Read-Host "已启动。按回车返回"
        }
        "6" {
            Set-Content -LiteralPath $markerAgy -Value $proxy
            Set-ProxyEnv
            if (-not (Test-ToolPath $agyApp.desktop)) {
                Write-Host "未找到桌面端程序: $($agyApp.desktop)" -ForegroundColor Red
                Read-Host "按回车返回"
                break
            }
            Write-Host ""
            Write-Host "正在以代理模式启动 Antigravity 桌面端..."
            Start-Process -FilePath $agyApp.desktop
            Read-Host "已启动。按回车返回"
        }
        "7" {
            Set-Content -LiteralPath $markerOc -Value $proxy
            Set-ProxyEnv
            Write-Host ""
            Write-Host "正在以代理模式启动 opencode CLI（退出后返回）..."
            Write-Host ""
            & $ocApp.cli
            Write-Host ""
            Read-Host "opencode CLI 已退出。按回车返回"
        }
        "8" {
            Set-Content -LiteralPath $markerAgy -Value $proxy
            Set-ProxyEnv
            Write-Host ""
            Write-Host "正在以代理模式启动 Antigravity CLI（退出后返回）..."
            Write-Host ""
            & $agyApp.cli
            Write-Host ""
            Read-Host "agy CLI 已退出。按回车返回"
        }
        "9" { exit }
        default { Write-Host "无效选项"; Start-Sleep -Seconds 1 }
    }
}
