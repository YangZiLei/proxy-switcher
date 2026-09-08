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

proxy_cfg="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
marker_oc="$( _psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.opencode")"
marker_agy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.antigravity")"
cli_oc="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.opencode.cli")"
cli_agy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.antigravity.cli")"
[[ -z "$cli_oc" ]] && cli_oc="opencode"
[[ -z "$cli_agy" ]] && cli_agy="agy"
[[ -n "$marker_oc" && -n "$marker_agy" && -n "$proxy_cfg" ]] || {
  print -u2 "错误：config.json 缺少 markers/proxy.url 配置项"
  exit 1
}
marker_oc="$HOME/$marker_oc"
marker_agy="$HOME/$marker_agy"

# 解析当前应注入的代理（配置 > 系统代理 > 常见端口），打印 "url|source"。
_psw_effective_proxy_any() {
  if [[ -f "$marker_oc" || -f "$marker_agy" ]]; then
    if [[ -f "$marker_oc" ]]; then _psw_effective_proxy opencode; else _psw_effective_proxy antigravity; fi
  else
    _psw_resolve_proxy
  fi
}

# 开启代理：写入实际可用的地址，而不是写死的配置值。
enable_marker() {
  local marker="$1" label="$2" line url src
  line="$(_psw_resolve_proxy)"
  url="${line%%|*}"; src="${line##*|}"
  print "$url" > "$marker"
  print ""
  print "[OK] $label 代理已开启 (CLI + 桌面)"
  print "     地址: $url (来源: $src)"
  print "     新终端里运行相应 -proxy 命令或桌面启动器将走代理"
}

# [0] 探测本机代理：列出可用地址，可选中写入 config.json。
pick_proxy() {
  print ""
  print "正在探测本机代理 (配置 > 系统代理 > 常见端口)..."
  local -a urls srcs
  local line url src i
  while IFS= read -r line; do
    url="${line%%|*}"; src="${line##*|}"
    [[ -n "$url" ]] && { urls+=("$url"); srcs+=("$src"); }
  done < <(_psw_available_proxies)
  if (( ${#urls} == 0 )); then
    print "[FAIL] 未发现任何可用代理端口。请先启动代理软件（Clash / Surge / FastLink 等）。"
    read -r "?按回车返回"
    return
  fi
  print "发现以下可用代理："
  for (( i = 1; i <= ${#urls}; i++ )); do
    print "  [$i] $urls[$i]  (来源: $srcs[$i])"
  done
  print "  [0] 取消"
  local sel
  read -r "sel?选择要写入 config.json 的地址序号: "
  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#urls} )); then
    python3 - "$PROXY_SWITCHER_CONFIG" "$urls[$sel]" <<'PY'
import json, sys
p, url = sys.argv[1], sys.argv[2]
cfg = json.load(open(p))
cfg.setdefault("proxy", {})["url"] = url
json.dump(cfg, open(p, "w"), ensure_ascii=False, indent=2)
print("saved")
PY
    print "[OK] 已将代理地址设为 $urls[$sel]"
  else
    print "已取消，未修改。"
  fi
  read -r "?按回车返回"
}

status_line() {
  local oc agy
  [[ -f "$marker_oc"  ]] && oc="开 (走代理)"  || oc="关 (直连)"
  [[ -f "$marker_agy" ]] && agy="开 (走代理)" || agy="关 (直连)"
  print "  opencode   : $oc"
  print "  antigravity: $agy"
}

while true; do
  clear 2>/dev/null || true
  _menu_line="$(_psw_effective_proxy_any)"
  _menu_url="${_menu_line%%|*}"; _menu_src="${_menu_line##*|}"
  print "================================================"
  print "   AI Agent 代理切换器 (macOS)"
  print "   (opencode / Antigravity 按工具独立控制)"
  print "   代理: $_menu_url (来源: $_menu_src)"
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
  print "  [0] 探测本机代理端口 (换代理软件后用这个)"
  print ""
  print "  [9] 退出"
  print -n "请选择: "
  read -r choice
  case "$choice" in
    0)
      pick_proxy
      ;;
    1)
      enable_marker "$marker_oc" "opencode"
      read -r "?按回车返回"
      ;;
    2)
      enable_marker "$marker_agy" "antigravity"
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
      enable_marker "$marker_oc" "opencode"
      print ""
      print "正在以代理模式启动 opencode CLI（退出后返回）..."
      print ""
      _psw_run_with_marker opencode command "$cli_oc"
      print ""
      read -r "?opencode CLI 已退出。按回车返回"
      ;;
    8)
      enable_marker "$marker_agy" "antigravity"
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
