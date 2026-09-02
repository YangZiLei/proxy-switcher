#!/bin/sh
# ============================================================
# proxy-switcher — one-line installer (top-level entry)
#
# 统一入口:检测平台后调用各平台已有安装器,并打印验证方式。
#   macOS   → macos/install.sh    (生成 .app + 图标 + 可选挂载 zsh 函数)
#   Windows → scripts/install.ps1 (生成 config.json + 开始菜单快捷方式)
#
# 用法:
#   仓库内:
#     ./install.sh                     # macOS 默认安装
#     ./install.sh --with-zshrc        # macOS + 挂载 opencode-proxy/agy-proxy 到 ~/.zshrc
#
#   发布后(curl | sh 管道模式,仅 macOS;可用 PROXY_SWITCHER_REPO_URL 覆盖):
#     curl -fsSL https://raw.githubusercontent.com/YangZiLei/proxy-switcher/main/install.sh | sh
#
# 幂等:重复执行安全(平台安装器内部已处理 config.json / .zshrc 已存在等情况)。
# 零依赖:仅用 POSIX sh + 平台自带工具;不下载任何额外二进制。
# ============================================================

set -e

# 定位脚本所在目录(仓库内运行时使用;管道模式下此目录不可用,走 clone 分支)
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# 管道模式(curl | sh)默认克隆的仓库地址;fork 部署可用 PROXY_SWITCHER_REPO_URL 覆盖
DEFAULT_REPO_URL="https://github.com/YangZiLei/proxy-switcher.git"

detect_os() {
  case "$(uname -s)" in
    Darwin)       echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)            echo "unknown" ;;
  esac
}

with_zshrc=0
for arg in "$@"; do
  case "$arg" in
    --with-zshrc) with_zshrc=1 ;;
  esac
done

print_verify() {
  platform=$1
  echo ""
  echo "================================================"
  echo "  安装完成。如何验证:"
  echo "  --------------------------------------------------"
  case "$platform" in
    macos)
      echo "  1. 双击 ~/Applications/代理切换.app（或跑 ~/.config/proxy-switcher/switcher.sh）"
      echo "  2. 双击 OpenCode / Antigravity 代理启动.app 启动桌面端"
      if [ "$with_zshrc" -eq 1 ]; then
        echo "  3. 新开一个终端，执行  type opencode-proxy  和  type agy-proxy"
        echo "     —— 应显示为函数定义(而非 'command not found')"
      else
        echo "  3. CLI 函数未挂载。若需要 opencode-proxy / agy-proxy，请再跑："
        echo "       ./install.sh --with-zshrc"
      fi
      ;;
    windows)
      echo "  1. 开始菜单中应出现 Proxy Switcher / OpenCode / Antigravity 快捷方式"
      echo "  2. 双击 switcher.bat 或上述快捷方式；奇数项是 opencode，偶数项是 Antigravity"
      echo "  3. （可选）在 PowerShell 配置文件中 dot-source profile\\profile-functions.ps1"
      echo "     之后新开 pwsh，使用 opencode-proxy / agy-proxy（不覆盖 opencode / agy）"
      echo "  4. 按需编辑仓库内 config.json 的 proxy.url 与桌面端路径"
      ;;
  esac
  echo "================================================"
}

# 临时克隆(仅 curl | sh 管道模式使用);结束前清理
# 注意:EXIT trap 的返回值会覆盖脚本退出码,cleanup 必须恒返回 0。
cleanup() {
  if [ -n "${TMP_DIR:-}" ]; then
    rm -rf "$TMP_DIR"
  fi
  return 0
}
trap cleanup EXIT INT TERM

case "$(detect_os)" in
  macos)
    if [ -f "$SCRIPT_DIR/macos/install.sh" ]; then
      # 仓库内直接运行
      zsh "$SCRIPT_DIR/macos/install.sh" "$@"
    else
      # 管道模式:浅克隆到临时目录再安装(默认本仓库,可用 PROXY_SWITCHER_REPO_URL 覆盖)
      REPO_URL="${PROXY_SWITCHER_REPO_URL:-$DEFAULT_REPO_URL}"
      TMP_DIR=$(mktemp -d)
      echo "==> 克隆仓库: $REPO_URL"
      git clone --depth 1 "$REPO_URL" "$TMP_DIR/proxy-switcher"
      zsh "$TMP_DIR/proxy-switcher/macos/install.sh" "$@"
    fi
    print_verify macos
    ;;
  windows)
    # 快捷方式必须指向本仓库内脚本;管道/临时克隆装完即删，无法工作。
    if [ ! -f "$SCRIPT_DIR/scripts/install.ps1" ]; then
      echo "Windows 不支持 curl | sh 管道安装（快捷方式需要指向本仓库里的脚本）。" >&2
      echo "请先克隆仓库，再生成配置并安装：" >&2
      echo "  git clone ${DEFAULT_REPO_URL}" >&2
      echo "  cd proxy-switcher" >&2
      echo "  pwsh -File scripts/install.ps1" >&2
      exit 1
    fi
    if ! command -v pwsh >/dev/null 2>&1; then
      echo "需要 PowerShell 7 (pwsh)。Windows PowerShell 5 (powershell.exe) 不能用来跑本安装器。" >&2
      echo "安装 pwsh 后在仓库根目录执行: pwsh -File scripts/install.ps1" >&2
      exit 1
    fi
    PS1_SCRIPT_WIN=$(cygpath -w "$SCRIPT_DIR/scripts/install.ps1" 2>/dev/null || printf '%s' "$SCRIPT_DIR/scripts/install.ps1")
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$PS1_SCRIPT_WIN"
    print_verify windows
    ;;
  *)
    echo "不支持的平台:$(uname -s) (仅支持 macOS / Windows)" >&2
    exit 1
    ;;
esac
