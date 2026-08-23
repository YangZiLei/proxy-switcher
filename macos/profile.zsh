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

_psw_config_get() {
  # $1 = json file, $2 = key path ("proxy.url" / "markers.opencode"). "" on failure.
  python3 - "$1" "$2" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d
    for k in sys.argv[2].split("."):
        v = v[k]
    if isinstance(v, str):
        print(v)
    elif isinstance(v, bool):
        print("true" if v else "false")
    else:
        print("")
except Exception:
    print("")
PY
}

_psw_run_with() {
  # $1 = marker name; remaining = command + args
  # 用临时前缀赋值注入 env，只作用于子进程，不 export 进当前会话
  # （核心承诺：不污染当前终端环境变量）。
  local marker="$1"; shift
  if [[ ! -f "$PROXY_SWITCHER_CONFIG" ]]; then
    print -u2 "proxy-switcher: 找不到配置文件 $PROXY_SWITCHER_CONFIG"
    return 1
  fi
  local url no_proxy
  url="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
  no_proxy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "no_proxy")"
  [[ -z "$no_proxy" ]] && no_proxy="127.0.0.1,localhost"
  if [[ -f "$HOME/$marker" && -n "$url" ]]; then
    # shellcheck disable=SC2097,SC2098 # 有意同时注入 NO_PROXY 与 no_proxy(部分工具只认小写),右值来自 local 变量而非环境
    HTTPS_PROXY="$url" HTTP_PROXY="$url" ALL_PROXY="$url" \
    NO_PROXY="$no_proxy" no_proxy="$no_proxy" \
      "$@"
  else
    "$@"
  fi
}

_psw_marker_name() {
  # $1 = 'opencode'|'antigravity' -> marker filename from config
  _psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.$1"
}

# opencode — run with proxy when ~/.opencode-proxy-on exists
function opencode-proxy() {
  local marker
  marker="$(_psw_marker_name "opencode")"
  [[ -n "$marker" ]] || { print -u2 "proxy-switcher: config 里没有 opencode 的 marker 配置"; return 1; }
  _psw_run_with "$marker" command opencode "$@"
}

# agy (Antigravity CLI)
function agy-proxy() {
  local marker
  marker="$(_psw_marker_name "antigravity")"
  [[ -n "$marker" ]] || { print -u2 "proxy-switcher: config 里没有 antigravity 的 marker 配置"; return 2; }
  _psw_run_with "$marker" command agy "$@"
}