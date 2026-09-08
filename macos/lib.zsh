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

# --- proxy auto-detect: config url -> OS system proxy -> common ports ---
# Lets users swap proxy apps (different ports) without editing config.json.
# Pure-SOCKS ports (7891/7898/10808/1080) are excluded: an http:// URL on a
# SOCKS-only listener breaks worse than direct.
_PSW_DEFAULT_PORTS="7897 7890 7892 7893 7899 7895 10809 2080 2081 8080 20171 20172"
# Last resolution source, for menu/launcher display (config|system|probe|marker).
_PSW_PROXY_SOURCE="config"

# True only when the endpoint is a real HTTP proxy: send a CONNECT tunnel
# request and require an "HTTP/x.y 2xx" reply. Rejects SOCKS-only listeners
# (silent) and HTTP API servers like the clash external controller (answers,
# but not 2xx) — injecting http:// into either breaks the tools.
_psw_url_reachable() {
  python3 - "$1" <<'PY' >/dev/null 2>&1
import socket, sys, urllib.parse
u = urllib.parse.urlparse(sys.argv[1])
host, port = u.hostname, u.port
if not host or not port:
    sys.exit(1)
try:
    s = socket.create_connection((host, port), timeout=0.25)
    s.settimeout(0.6)
    s.sendall(b"CONNECT example.com:443 HTTP/1.0\r\nHost: example.com:443\r\n\r\n")
    data = s.recv(64)
    s.close()
    first = data.split(b"\r\n", 1)[0]
    import re
    sys.exit(0 if re.match(rb"^HTTP/\d(\.\d)?\s+2\d\d", first) else 1)
except Exception:
    sys.exit(1)
PY
}

# OS-level (system) proxy, e.g. set by Clash "系统代理" / Surge / FastLink.
# Prints http://host:port or nothing when disabled.
_psw_system_proxy() {
  [[ "$(uname)" == "Darwin" ]] || return 0
  scutil --proxy 2>/dev/null | python3 -c "
import re, sys
d = {}
for line in sys.stdin:
    m = re.match(r'\s*(\w+)\s*:\s*(.+?)\s*$', line)
    if m: d[m.group(1)] = m.group(2)
for proto in ('HTTPS', 'HTTP'):
    if d.get(proto + 'Enable') == '1' and d.get(proto + 'Proxy') and d.get(proto + 'Port'):
        print('http://%s:%s' % (d[proto + 'Proxy'], d[proto + 'Port']))
        break
" 2>/dev/null
}

_psw_auto_detect_enabled() {
  local v
  v="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.auto_detect")"
  # absent (prints "") or "true" -> on; explicit false -> off
  [[ "$v" != "false" ]]
}

# Ordered, de-duplicated candidates, one "url|source" per line.
_psw_candidate_urls() {
  python3 - "$PROXY_SWITCHER_CONFIG" <<'PY'
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    cfg = {}
seen = set()
def add(url, src):
    if isinstance(url, str):
        url = url.strip()
    if not url or url in seen:
        return
    seen.add(url)
    print("%s|%s" % (url, src))
px = cfg.get("proxy", {}) if isinstance(cfg.get("proxy", {}), dict) else {}
add(px.get("url", ""), "config")
PY
  local sys
  sys="$(_psw_system_proxy)"
  [[ -n "$sys" ]] && print -r -- "$sys|system"
  python3 - "$PROXY_SWITCHER_CONFIG" "$_PSW_DEFAULT_PORTS" <<'PY'
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    cfg = {}
seen = set()
def add(url, src):
    if isinstance(url, str):
        url = url.strip()
    if not url or url in seen:
        return
    seen.add(url)
    print("%s|%s" % (url, src))
px = cfg.get("proxy", {}) if isinstance(cfg.get("proxy", {}), dict) else {}
for c in px.get("candidates", []) or []:
    add(c, "config-candidates")
for p in px.get("candidate_ports", []) or []:
    try:
        add("http://127.0.0.1:%d" % int(p), "config-ports")
    except (TypeError, ValueError):
        pass
for p in sys.argv[2].split():
    add("http://127.0.0.1:%s" % p, "probe")
PY
}

# Resolve the URL to inject: first reachable candidate. Prints "url|source".
# Falls back to the config url when detection is off or nothing answers.
_psw_resolve_proxy() {
  local url src line
  if ! _psw_auto_detect_enabled; then
    url="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
    _PSW_PROXY_SOURCE="config"
    print -r -- "$url|config"
    return 0
  fi
  while IFS= read -r line; do
    url="${line%%|*}"; src="${line##*|}"
    if [[ -n "$url" ]] && _psw_url_reachable "$url"; then
      _PSW_PROXY_SOURCE="$src"
      print -r -- "$url|$src"
      return 0
    fi
  done < <(_psw_candidate_urls | awk -F'|' '!seen[$0]++')
  url="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
  _PSW_PROXY_SOURCE="config"
  print -r -- "$url|config"
}

# All reachable candidates, one "url|source" per line (picker menu).
_psw_available_proxies() {
  local url src line
  while IFS= read -r line; do
    url="${line%%|*}"; src="${line##*|}"
    if [[ -n "$url" ]] && _psw_url_reachable "$url"; then
      print -r -- "$url|$src"
    fi
  done < <(_psw_candidate_urls | awk -F'|' '!seen[$0]++')
}

# Effective URL for an app: marker-pinned URL while it answers, else resolve
# (so a swapped proxy app is picked up without editing config.json).
_psw_effective_proxy() {
  local app="$1" marker murl
  marker="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.$app")"
  if [[ -n "$marker" && -f "$HOME/$marker" ]]; then
    murl="$(cat "$HOME/$marker" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$murl" == http://* || "$murl" == https://* ]] && _psw_url_reachable "$murl"; then
      _PSW_PROXY_SOURCE="marker"
      print -r -- "$murl|marker"
      return 0
    fi
  fi
  _psw_resolve_proxy
}

# Run a command with proxy env IFF the app's marker exists.
# Prefix assignment only — does not export into the current shell.
_psw_run_with_marker() {
  local app="$1"; shift
  if [[ ! -f "$PROXY_SWITCHER_CONFIG" ]]; then
    print -u2 "proxy-switcher: 找不到配置文件 $PROXY_SWITCHER_CONFIG"
    return 1
  fi
  local url np marker line
  line="$(_psw_effective_proxy "$app")"
  url="${line%%|*}"
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
  local url np marker line src
  line="$(_psw_effective_proxy "$app")"
  url="${line%%|*}"; src="${line##*|}"
  _PSW_PROXY_SOURCE="$src"
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
