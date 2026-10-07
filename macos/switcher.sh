#!/bin/zsh
# shellcheck shell=bash
# ============================================================
# proxy-switcher for macOS — 主菜单
# opencode / Antigravity (agy) 按工具独立代理控制
#
# 原理：
#   每个工具在 $HOME 下有标记文件（名字见 config.json）。
#   三态模式（_psw_get_mode / _psw_set_mode）：
#     强制代理 (…-on)   -> 启动/CLI 总是注入
#     强制直连 (…-off)  -> 总是直连
#     自动 (无标记)     -> 启动时探测，代理存活才注入
#   注入只发生在启动器/包装函数里，只向子进程注入
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
# 经 .command 双击拉起时环境变量可能不完整，先补齐 PATH（lsof / node）
_psw_prepare_path

[[ -f "$PROXY_SWITCHER_CONFIG" ]] || {
  print -u2 "错误：找不到配置文件 $PROXY_SWITCHER_CONFIG"
  exit 1
}

proxy_cfg="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
marker_oc="$( _psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.opencode")"
marker_agy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.antigravity")"
marker_gem="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.gemini")"
marker_grk="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.grok")"
[[ -z "$marker_oc" ]] && marker_oc=".opencode-proxy-on"
[[ -z "$marker_agy" ]] && marker_agy=".agy-proxy-on"
[[ -z "$marker_gem" ]] && marker_gem=".gemini-proxy-on"
[[ -z "$marker_grk" ]] && marker_grk=".grok-proxy-on"

cli_oc="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.opencode.cli")"
cli_agy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.antigravity.cli")"
cli_gem="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.gemini.cli")"
cli_grk="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.grok.cli")"
[[ -z "$cli_oc" ]] && cli_oc="opencode"
[[ -z "$cli_agy" ]] && cli_agy="agy"
[[ -z "$cli_grk" ]] && cli_grk="grok"

[[ -n "$proxy_cfg" ]] || {
  print -u2 "错误：config.json 缺少 proxy.url 配置项"
  exit 1
}

# 解析当前应注入的代理（配置 > 系统代理 > 常见端口），打印 "url|source"。
_psw_effective_proxy_any() {
  local app m
  for app in opencode antigravity gemini grok; do
    m="$(_psw_marker_name "$app")"
    if [[ -n "$m" && -f "$HOME/$m" ]]; then
      _psw_effective_proxy "$app"
      return
    fi
  done
  _psw_resolve_proxy
}

# 三态模式显示名
mode_label() {
  case "$(_psw_get_mode "$1")" in
    proxy)  print "强制代理" ;;
    direct) print "强制直连" ;;
    *)      print "自动 (探测，存活则注入)" ;;
  esac
}

# 模式循环：自动 -> 强制代理 -> 强制直连 -> 自动
next_mode() {
  case "$(_psw_get_mode "$1")" in
    auto)   print proxy ;;
    proxy)  print direct ;;
    *)      print auto ;;
  esac
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
    print "  [$i] ${urls[$i]}  (来源: ${srcs[$i]})"
  done
  print "  [0] 取消"
  local sel
  read -r "sel?选择要写入 config.json 的地址序号: "
  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#urls} )); then
    python3 - "$PROXY_SWITCHER_CONFIG" "${urls[$sel]}" <<'PY'
import json, sys
p, url = sys.argv[1], sys.argv[2]
cfg = json.load(open(p))
cfg.setdefault("proxy", {})["url"] = url
json.dump(cfg, open(p, "w"), ensure_ascii=False, indent=2)
    print("saved")
PY
    _psw_config_reload   # 缓存失效，下一帧读新值
    print "[OK] 已将代理地址设为 ${urls[$sel]}"
  else
    print "已取消，未修改。"
  fi
  read -r "?按回车返回"
}

status_line() {
  print "  opencode   : $(mode_label opencode)"
  print "  antigravity: $(mode_label antigravity)"
  print "  Gemini     : $(mode_label gemini)"
  print "  Grok       : $(mode_label grok)"
}

while true; do
  clear 2>/dev/null || true
  _menu_line="$(_psw_effective_proxy_any)"
  _menu_url="${_menu_line%%|*}"; _menu_src="${_menu_line##*|}"
  print "================================================"
  print "   AI Agent 代理切换器 (macOS)"
  print "   (opencode / Antigravity / Gemini / Grok)"
  print "   当前可用代理: $_menu_url (来源: $_menu_src)"
  print "================================================"
  status_line
  print ""
  print "  ── opencode ──────────────────────"
  print "  [1] 切换模式 (自动 / 强制代理 / 强制直连)"
  print "  [5] 启动 桌面端 (按当前模式注入)"
  print "  [7] 启动 CLI (本窗口, 按当前模式)"
  print ""
  print "  ── Antigravity ───────────────────"
  print "  [2] 切换模式 (自动 / 强制代理 / 强制直连)"
  print "  [6] 启动 桌面端 (按当前模式注入)"
  print "  [8] 启动 CLI (本窗口, 按当前模式)"
  print ""
  print "  ── Gemini ────────────────────────"
  print "  [3] 切换模式 (自动 / 强制代理 / 强制直连)"
  print "  [4] 启动 桌面端 (按当前模式注入)"
  if [[ -n "$cli_gem" ]]; then
    print "  [g] 启动 CLI (本窗口, 按当前模式)"
  fi
  print ""
  print "  ── Grok (xAI) ────────────────────"
  print "  [k] 切换模式 (自动 / 强制代理 / 强制直连)"
  print "  [x] 启动 CLI (本窗口, 按当前模式)"
  print ""
  print "  [0] 探测本机代理端口 (换代理软件后用这个)"
  print ""
  print "  [9] 退出 (或输入 q)"
  print -n "请选择: "
  read -r choice
  case "$choice" in
    0)
      pick_proxy
      ;;
    1)
      _psw_set_mode opencode "$(next_mode opencode)"
      ;;
    2)
      _psw_set_mode antigravity "$(next_mode antigravity)"
      ;;
    3)
      _psw_set_mode gemini "$(next_mode gemini)"
      ;;
    4)
      print ""
      print "正在启动 Gemini 桌面端..."
      print ""
      "$SCRIPT_DIR/launch.sh" gemini
      print ""
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
      print ""
      print "正在启动 opencode CLI（退出后返回）..."
      print ""
      _psw_run_with_marker opencode command "$cli_oc"
      print ""
      read -r "?opencode CLI 已退出。按回车返回"
      ;;
    8)
      print ""
      print "正在启动 Antigravity CLI（退出后返回）..."
      print ""
      _psw_run_with_marker antigravity command "$cli_agy"
      print ""
      read -r "?agy CLI 已退出。按回车返回"
      ;;
    g|G)
      if [[ -n "$cli_gem" ]]; then
        print ""
        print "正在启动 Gemini CLI（退出后返回）..."
        print ""
        _psw_run_with_marker gemini command "$cli_gem"
        print ""
        read -r "?Gemini CLI 已退出。按回车返回"
      else
        print "未配置 Gemini CLI"; sleep 1
      fi
      ;;
    k|K)
      _psw_set_mode grok "$(next_mode grok)"
      ;;
    x|X)
      print ""
      print "正在启动 Grok CLI（退出后返回）..."
      print ""
      _psw_run_with_marker grok command "$cli_grk"
      print ""
      read -r "?Grok CLI 已退出。按回车返回"
      ;;
    9|q|Q) exit 0 ;;
    *) print "无效选项"; sleep 1 ;;
  esac
done
