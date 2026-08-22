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

_psw_proxy_env() {
  # Export proxy env vars into the current shell when the marker is present.
  # Returns 0 if proxy was injected, 1 otherwise.
  local marker="$1"
  if [[ ! -f "$PROXY_SWITCHER_CONFIG" ]]; then
    print -u2 "proxy-switcher: 找不到配置文件 $PROXY_SWITCHER_CONFIG"
    return 1
  fi
  local url no_proxy marker_path
  url="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
  no_proxy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "no_proxy")"
  marker_path="$HOME/$marker"
  [[ -z "$no_proxy" ]] && no_proxy="127.0.0.1,localhost"
  if [[ -f "$marker_path" && -n "$url" ]]; then
    export HTTPS_PROXY="$url" HTTP_PROXY="$url" ALL_PROXY="$url"
    export NO_PROXY="$no_proxy" no_proxy="$no_proxy"
    return 0
  fi
  return 1
}

_psw_run_with() {
  # $1 = marker name; remaining = command + args
  local marker="$1"; shift
  _psw_proxy_env "$marker" >/dev/null
  "$@"
}

_psw_marker_name() {
  # $1 = 'opencode'|'antigravity' -> marker filename from config
  _psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.$1"
}

# opencode — run with proxy when ~/.opencode-proxy-on exists
function opencode-proxy() {
  local marker
  marker="$(_psw_marker_name "opencode")"
  [[ -n "$marker" ]] || { print -u2 "proxy-switcher: config 里没有 opencode 的 marker 配置"; return 1 }
  _psw_run_with "$marker" command opencode "$@"
}

# agy (Antigravity CLI)
function agy-proxy() {
  local marker
  marker="$(_psw_marker_name "antigravity")"
  [[ -n "$marker" ]] || { print -u2 "proxy-switcher: config 里没有 antigravity 的 marker 配置"; return 2 }
  _psw_run_with "$marker" command agy "$@"
}