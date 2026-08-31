# shellcheck shell=bash
# ============================================================
# proxy-switcher for macOS — 可选的 zsh 函数（可选安装）
#
# 在 ~/.zshrc 中添加：
#   . "$HOME/.config/proxy-switcher/profile.zsh"
#
# 提供两个命令：
#   opencode-proxy   标记开启时以代理模式运行 opencode
#   agy-proxy        标记开启时以代理模式运行 agy
#
# 标记文件在 $HOME 下（由 switcher.sh 切换）：
#   ~/.opencode-proxy-on
#   ~/.agy-proxy-on
#
# 只影响当前 shell 中这些函数的子进程，不碰全局环境变量。
# ============================================================

: "${PROXY_SWITCHER_CONFIG:=$HOME/.config/proxy-switcher/config.json}"

# %x = 当前被 source 的文件（不是交互 shell 的 $0）
# shellcheck source=lib.zsh
# shellcheck disable=SC1091,SC2296,SC2298 # zsh ${(%):-%x}:A:h = dir of sourced file
. "${${(%):-%x}:A:h}/lib.zsh"

# opencode — run with proxy when marker exists
function opencode-proxy() {
  local cli
  cli="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.opencode.cli")"
  [[ -n "$cli" ]] || { print -u2 "proxy-switcher: config 里没有 opencode 的 cli 配置"; return 1; }
  _psw_run_with_marker opencode command "$cli" "$@"
}

# agy (Antigravity CLI)
function agy-proxy() {
  local cli
  cli="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.antigravity.cli")"
  [[ -n "$cli" ]] || { print -u2 "proxy-switcher: config 里没有 antigravity 的 cli 配置"; return 2; }
  _psw_run_with_marker antigravity command "$cli" "$@"
}
