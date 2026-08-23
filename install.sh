#!/bin/sh
# ============================================================
# proxy-switcher — one-line installer (top-level entry)
#
# 统一入口:检测平台后调用各平台已有安装器,并打印验证方式。
#   macOS   → macos/install.sh    (生成 .app + 图标 + 可选挂载 zsh 函数)
#   Windows → scripts/install.ps1 (创建开始菜单快捷方式)
#
# 用法:
#   仓库内:
#     ./install.sh                     # macOS 默认安装
#     ./install.sh --with-zshrc        # macOS + 挂载 opencode-proxy/agy-proxy 到 ~/.zshrc
#
#   发布后(curl | sh 管道模式,需设置 PROXY_SWITCHER_REPO_URL):
#     curl -fsSL <repo>/install.sh | PROXY_SWITCHER_REPO_URL=<repo> sh
#
# 幂等:重复执行安全(平台安装器内部已处理 config.json / .zshrc 已存在等情况)。
# 零依赖:仅用 POSIX sh + 平台自带工具;不下载任何额外二进制。
# ============================================================

set -e

# 定位脚本所在目录(仓库内运行时使用;管道模式下此目录不可用,走 clone 分支)
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

detect_os() {
  case "$(uname -s)" in
    Darwin)       echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)            echo "unknown" ;;
  esac
}

print_verify() {
  echo ""
  echo "================================================"
  echo "  安装完成。如何验证:"
  echo "  --------------------------------------------------"
  echo "  1. 新开一个终端"
  echo "  2. 执行  type opencode-proxy  和  type agy-proxy"
  echo "     —— 应显示为函数定义(而非 'command not found')"
  echo "  3. 执行  opencode-proxy        —— 应能正常启动 opencode"
  echo "  --------------------------------------------------"
  echo "  说明:CLI 代理注入函数来自 profile.zsh /"
  echo "       profile-functions.ps1,需先完成对应平台的挂载步骤"
  echo "       (macOS: install.sh --with-zshrc;"
  echo "        Windows: dot-source profile-functions.ps1)"
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
    elif [ -n "${PROXY_SWITCHER_REPO_URL:-}" ]; then
      # 管道模式:浅克隆到临时目录再安装
      TMP_DIR=$(mktemp -d)
      echo "==> 克隆仓库: $PROXY_SWITCHER_REPO_URL"
      git clone --depth 1 "$PROXY_SWITCHER_REPO_URL" "$TMP_DIR/proxy-switcher"
      zsh "$TMP_DIR/proxy-switcher/macos/install.sh" "$@"
    else
      echo "错误:未找到仓库文件。" >&2
      echo "仓库内请直接运行 ./install.sh;" >&2
      echo "curl | sh 安装请设置 PROXY_SWITCHER_REPO_URL 环境变量。" >&2
      exit 1
    fi
    print_verify
    ;;
  windows)
    # Windows 侧 install.ps1 已覆盖开始菜单快捷方式创建,此处只做入口统一
    if [ -f "$SCRIPT_DIR/scripts/install.ps1" ]; then
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/scripts/install.ps1" "$@"
    elif [ -n "${PROXY_SWITCHER_REPO_URL:-}" ]; then
      TMP_DIR=$(mktemp -d)
      git clone --depth 1 "$PROXY_SWITCHER_REPO_URL" "$TMP_DIR/proxy-switcher"
      powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$TMP_DIR/proxy-switcher/scripts/install.ps1" "$@"
    else
      echo "错误:未找到仓库文件。请先 git clone 本仓库,或设置 PROXY_SWITCHER_REPO_URL。" >&2
      exit 1
    fi
    print_verify
    ;;
  *)
    echo "不支持的平台:$(uname -s) (仅支持 macOS / Windows)" >&2
    exit 1
    ;;
esac
