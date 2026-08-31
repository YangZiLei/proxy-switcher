# shellcheck shell=bash
# ============================================================
# proxy-switcher — shared zsh helpers (config + env inject)
# Sourced by switcher.sh, launch.sh, profile.zsh.
# ============================================================

: "${PROXY_SWITCHER_CONFIG:=$HOME/.config/proxy-switcher/config.json}"

_psw_config_get() {
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

_psw_no_proxy() {
  local n
  n="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "no_proxy")"
  [[ -z "$n" ]] && n="127.0.0.1,localhost"
  print -r -- "$n"
}

# Run a command with proxy env IFF the app's marker exists.
# Prefix assignment only — does not export into the current shell.
_psw_run_with_marker() {
  local app="$1"; shift
  if [[ ! -f "$PROXY_SWITCHER_CONFIG" ]]; then
    print -u2 "proxy-switcher: 找不到配置文件 $PROXY_SWITCHER_CONFIG"
    return 1
  fi
  local url np marker
  url="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
  np="$(_psw_no_proxy)"
  marker="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.$app")"
  if [[ -n "$marker" && -f "$HOME/$marker" && -n "$url" ]]; then
    # shellcheck disable=SC2097,SC2098 # 有意同时注入 NO_PROXY 与 no_proxy,右值来自 local 而非环境
    HTTPS_PROXY="$url" HTTP_PROXY="$url" ALL_PROXY="$url" \
    NO_PROXY="$np" no_proxy="$np" \
      "$@"
  else
    "$@"
  fi
}

# For desktop launch: drop inherited proxy vars, then inject IFF marker is on.
# Return 0 if injecting, 1 if starting direct. Exports into the current
# (short-lived launcher) process so the spawned app inherits them.
_psw_prepare_desktop_env() {
  local app="$1"
  local url np marker
  url="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
  np="$(_psw_no_proxy)"
  marker="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.$app")"
  unset HTTPS_PROXY HTTP_PROXY ALL_PROXY https_proxy http_proxy all_proxy NO_PROXY no_proxy
  if [[ -n "$marker" && -f "$HOME/$marker" && -n "$url" ]]; then
    export HTTPS_PROXY="$url" HTTP_PROXY="$url" ALL_PROXY="$url"
    export NO_PROXY="$np" no_proxy="$np"
    return 0
  fi
  return 1
}
