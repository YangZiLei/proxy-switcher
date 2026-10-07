# shellcheck shell=bash
# ============================================================
# proxy-switcher for macOS — 可选的 zsh 函数（可选安装）
#
# 在 ~/.zshrc 中添加：
#   . "$HOME/.config/proxy-switcher/profile.zsh"
#
# 提供常用命令：
#   proxy-switch / psw / switcher  打开主菜单（三态模式切换、启动应用）
#   opencode-proxy  按当前模式运行 opencode：自动=探测到代理才注入；
#                   强制代理=总是注入；强制直连=直连
#   agy-proxy       同上，运行 agy
#   gemini-proxy    按当前模式运行 Gemini（桌面端或 CLI）
#   grok-proxy      按当前模式运行 xAI Grok Build TUI CLI
#
# 模式标记在 $HOME 下（由 switcher.sh 切换）：
#   ~/.opencode-proxy-on / ~/.agy-proxy-on / ~/.gemini-proxy-on / ~/.grok-proxy-on   = 强制代理
#   ~/.opencode-proxy-off / ~/.agy-proxy-off / ~/.gemini-proxy-off / ~/.grok-proxy-off = 强制直连
#   两者都无 = 自动（探测，代理存活则注入）
#
# 只影响当前 shell 中这些函数的子进程，不碰全局环境变量。
# ============================================================

: "${PROXY_SWITCHER_CONFIG:=$HOME/.config/proxy-switcher/config.json}"

# %x = 当前被 source 的文件（不是交互 shell 的 $0）
# shellcheck source=lib.zsh
# shellcheck disable=SC1091,SC2296,SC2298 # zsh ${(%):-%x}:A:h = dir of sourced file
. "${${(%):-%x}:A:h}/lib.zsh"

# 主菜单（等价于双击 ~/Applications/代理切换.app）
# 新终端里直接敲 proxy-switch / psw / switcher 即可打开
function proxy-switch() {
  local sw="$HOME/.config/proxy-switcher/switcher.sh"
  if [[ ! -x "$sw" ]]; then
    # shellcheck disable=SC2296,SC2298 # zsh ${(%):-%x}:A:h = dir of sourced file
    sw="${${(%):-%x}:A:h}/switcher.sh"
  fi
  [[ -x "$sw" ]] || { print -u2 "proxy-switcher: 找不到菜单脚本 $sw，请重跑 macos/install.sh"; return 1; }
  "$sw"
}

alias psw=proxy-switch
alias switcher=proxy-switch

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

# gemini (Gemini 桌面端或 CLI 代理启动)
function gemini-proxy() {
  local cli
  cli="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.gemini.cli")"
  if [[ -n "$cli" ]]; then
    _psw_run_with_marker gemini command "$cli" "$@"
  else
    local sw="$HOME/.config/proxy-switcher/launch.sh"
    if [[ ! -x "$sw" ]]; then
      # shellcheck disable=SC2296,SC2298 # zsh ${(%):-%x}:A:h = dir of sourced file
      sw="${${(%):-%x}:A:h}/launch.sh"
    fi
    "$sw" gemini "$@"
  fi
}

# grok (xAI Grok Build TUI CLI 代理启动)
function grok-proxy() {
  local cli
  cli="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.grok.cli")"
  [[ -z "$cli" ]] && cli="grok"
  _psw_run_with_marker grok command "$cli" "$@"
}
