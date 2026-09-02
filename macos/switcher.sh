#!/bin/zsh
# shellcheck shell=bash
# ============================================================
# proxy-switcher for macOS — 主菜单
# opencode / Antigravity (agy) 按工具独立代理开关
#
# 原理：
#   每个工具在 $HOME 下有一个标记文件（见 config.json）。
#   开启=写标记文件；关闭=删除标记文件。profile.zsh 中的
#   函数在启动时读取标记，只向子进程注入
#   HTTPS_PROXY/HTTP_PROXY/ALL_PROXY——不触碰全局环境变量。
#
# 用法：
#   ~/.config/proxy-switcher/switcher.sh
# ============================================================

: "${PROXY_SWITCHER_CONFIG:=$HOME/.config/proxy-switcher/config.json}"

# launch.sh / lib.zsh 与本脚本同目录安装；按脚本自身位置解析，不硬编码
# ~/.config/proxy-switcher，自定义目录布局（仓库内直接运行等）也能找到。
SCRIPT_DIR="${0:A:h}"
# shellcheck disable=SC1091
# shellcheck source=lib.zsh
. "$SCRIPT_DIR/lib.zsh"

[[ -f "$PROXY_SWITCHER_CONFIG" ]] || {
  print -u2 "错误：找不到配置文件 $PROXY_SWITCHER_CONFIG"
  exit 1
}

proxy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
marker_oc="$( _psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.opencode")"
marker_agy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.antigravity")"
cli_oc="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.opencode.cli")"
cli_agy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.antigravity.cli")"
[[ -z "$cli_oc" ]] && cli_oc="opencode"
[[ -z "$cli_agy" ]] && cli_agy="agy"
[[ -n "$marker_oc" && -n "$marker_agy" && -n "$proxy" ]] || {
  print -u2 "错误：config.json 缺少 markers/proxy.url 配置项"
  exit 1
}
marker_oc="$HOME/$marker_oc"
marker_agy="$HOME/$marker_agy"

status_line() {
  local oc agy
  [[ -f "$marker_oc"  ]] && oc="开 (走代理)"  || oc="关 (直连)"
  [[ -f "$marker_agy" ]] && agy="开 (走代理)" || agy="关 (直连)"
  print "  opencode   : $oc"
  print "  antigravity: $agy"
}

while true; do
  clear 2>/dev/null || true
  print "================================================"
  print "   AI Agent 代理切换器 (macOS)"
  print "   (opencode / Antigravity 按工具独立控制)"
  print "   代理: $proxy"
  print "================================================"
  status_line
  print ""
  print "  ── opencode ──────────────────────"
  print "  [1] 开启 代理 (CLI + 桌面)"
  print "  [3] 关闭 代理 (直连)"
  print "  [5] 启动 桌面端 (按标记注入代理)"
  print "  [7] 开启代理并启动 CLI (本窗口)"
  print ""
  print "  ── Antigravity ───────────────────"
  print "  [2] 开启 代理 (CLI + 桌面)"
  print "  [4] 关闭 代理 (直连)"
  print "  [6] 启动 桌面端 (按标记注入代理)"
  print "  [8] 开启代理并启动 CLI (本窗口)"
  print ""
  print "  [9] 退出"
  print -n "请选择: "
  read -r choice
  case "$choice" in
    1)
      print "$proxy" > "$marker_oc"
      print ""
      print "[OK] opencode 代理已开启 (CLI + 桌面)"
      print "     新终端里运行 'opencode-proxy' 或桌面启动器将走代理"
      read -r "?按回车返回"
      ;;
    2)
      print "$proxy" > "$marker_agy"
      print ""
      print "[OK] antigravity 代理已开启 (CLI + 桌面)"
      print "     新终端里运行 'agy-proxy' 或桌面启动器将走代理"
      read -r "?按回车返回"
      ;;
    3)
      rm -f "$marker_oc"
      print ""
      print "[OK] opencode 已恢复直连"
      read -r "?按回车返回"
      ;;
    4)
      rm -f "$marker_agy"
      print ""
      print "[OK] antigravity 已恢复直连"
      read -r "?按回车返回"
      ;;
    5)
      print ""
      print "正在启动 OpenCode 桌面端..."
      print ""
      "$SCRIPT_DIR/launch.sh" opencode
      print ""
      read -r "?按回车返回"
      ;;
    6)
      print ""
      print "正在启动 Antigravity 桌面端..."
      print ""
      "$SCRIPT_DIR/launch.sh" antigravity
      print ""
      read -r "?按回车返回"
      ;;
    7)
      print "$proxy" > "$marker_oc"
      print ""
      print "正在以代理模式启动 opencode CLI（退出后返回）..."
      print ""
      _psw_run_with_marker opencode command "$cli_oc"
      print ""
      read -r "?opencode CLI 已退出。按回车返回"
      ;;
    8)
      print "$proxy" > "$marker_agy"
      print ""
      print "正在以代理模式启动 Antigravity CLI（退出后返回）..."
      print ""
      _psw_run_with_marker antigravity command "$cli_agy"
      print ""
      read -r "?agy CLI 已退出。按回车返回"
      ;;
    9) exit 0 ;;
    *) print "无效选项"; sleep 1 ;;
  esac
done
