# shellcheck shell=bash
# ============================================================
# proxy-switcher — shared zsh helpers (config + env inject)
# Sourced by switcher.sh, launch.sh, profile.zsh.
# ============================================================

: "${PROXY_SWITCHER_CONFIG:=$HOME/.config/proxy-switcher/config.json}"

# --- 配置缓存 ------------------------------------------------------------
# 一次 python3 把整份 config 摊平成 key=value 存进关联数组，后续查找不再起
# 进程（菜单每帧原本要起 5~7 个 python3 ≈ 0.3s）。写配置后调 _psw_config_reload。
typeset -gA _PSW_CFG
typeset -ga _PSW_PATH_EXTRA
typeset -g _PSW_CFG_READY=0

_psw_config_load() {
  (( _PSW_CFG_READY )) && return 0
  [[ -f "$PROXY_SWITCHER_CONFIG" ]] || return 0
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == "path.extra."* ]]; then
      _PSW_PATH_EXTRA+=("${line#path.extra.}")
    else
      _PSW_CFG[${line%%=*}]="${line#*=}"
    fi
  done < <(python3 - "$PROXY_SWITCHER_CONFIG" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
out = []
def walk(v, prefix):
    if isinstance(v, dict):
        for k, vv in v.items():
            walk(vv, "%s.%s" % (prefix, k) if prefix else k)
        return
    if isinstance(v, str):
        s = v
    elif isinstance(v, bool):
        s = "true" if v else "false"
    else:
        return
    if "\n" in s or "\r" in s:
        return
    out.append("%s=%s" % (prefix, s))
walk(d, "")
pe = d.get("path") if isinstance(d.get("path"), dict) else {}
for p in pe.get("extra") or []:
    if isinstance(p, str) and p.strip() and "\n" not in p:
        out.append("path.extra.%s" % p.strip())
sys.stdout.write("\n".join(out))
PY
)
  _PSW_CFG_READY=1
}

_psw_config_reload() {
  unset _PSW_CFG _PSW_PATH_EXTRA
  typeset -gA _PSW_CFG
  typeset -ga _PSW_PATH_EXTRA
  _PSW_CFG_READY=0
}

_psw_config_get() {   # $1=config 路径（保留兼容） $2=点分 key
  _psw_config_load
  print -r -- "${_PSW_CFG[$2]-}"
}

# --- PATH 兜底 -----------------------------------------------------------
# 经 Finder 双击 .command 拉起时环境变量可能不完整（PATH 只有基础目录），
# 没有 /usr/sbin → lsof 找不到（白屏恢复要靠它找 language_server 端口）。
# 这里补齐标准目录，再追加 config 里 path.extra 的机器特定目录（自管 node 等）。
# 只在 switcher.sh / launch.sh 里调用：profile.zsh 不调，避免拖慢每个新 shell。
_psw_prepare_path() {
  local d
  for d in /usr/local/bin /opt/homebrew/bin /usr/bin /bin /usr/sbin /sbin; do
    [[ -d "$d" && ":$PATH:" != *":$d:"* ]] && PATH="$PATH:$d"
  done
  _psw_config_load
  for d in "${_PSW_PATH_EXTRA[@]}"; do
    [[ -d "$d" && ":$PATH:" != *":$d:"* ]] && PATH="$PATH:$d"
  done
  export PATH
}

_psw_no_proxy() {
  local n
  n="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "no_proxy")"
  [[ -z "$n" ]] && n="127.0.0.1,localhost"
  print -r -- "$n"
}

# --- macOS 通知中心（尽力而为）---------------------------------------------
# 静默启动模式的主要反馈通道；SSH 等无 Aqua 会话场景或 osascript 缺失时静默跳过。
# 同步执行（osascript ~0.3s），避免后台子进程随宿主脚本退出被 SIGHUP 掐断。
_psw_notify() {   # $1=标题 $2=正文 $3="sound"(可选，失败/警告时用)
  [[ "$(uname)" == "Darwin" ]] || return 0
  command -v osascript >/dev/null 2>&1 || return 0
  local t b snd
  t="${1//\\/\\\\}"; t="${t//\"/\\\"}"
  b="${2//\\/\\\\}"; b="${b//\"/\\\"}"
  snd=""
  [[ "$3" == "sound" ]] && snd=' sound name "Ping"'
  osascript -e "display notification \"$b\" with title \"$t\"$snd" >/dev/null 2>&1
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

# First REACHABLE candidate, prints "url|source" and returns 0; return 1 when
# nothing answers. Unlike _psw_resolve_proxy this never falls back, so callers
# can distinguish "proxy alive" from "direct only" (auto mode needs that).
_psw_resolve_alive() {
  local line url src
  if ! _psw_auto_detect_enabled; then
    url="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
    if [[ -n "$url" ]] && _psw_url_reachable "$url"; then
      _PSW_PROXY_SOURCE="config"
      print -r -- "$url|config"
      return 0
    fi
    return 1
  fi
  while IFS= read -r line; do
    url="${line%%|*}"; src="${line##*|}"
    if [[ -n "$url" ]] && _psw_url_reachable "$url"; then
      _PSW_PROXY_SOURCE="$src"
      print -r -- "$url|$src"
      return 0
    fi
  done < <(_psw_candidate_urls | awk -F'|' '!seen[$0]++')
  return 1
}

# Resolve the URL to inject: first reachable candidate. Prints "url|source".
# Falls back to the config url when detection is off or nothing answers.
_psw_resolve_proxy() {
  local line url
  if line="$(_psw_resolve_alive)"; then
    print -r -- "$line"
    return 0
  fi
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
_psw_marker_name() {   # $1=app -> 标记文件名（缺省时智能回落）
  local m
  m="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.$1")"
  if [[ -z "$m" ]]; then
    case "$1" in
      opencode)    m=".opencode-proxy-on" ;;
      antigravity) m=".agy-proxy-on" ;;
      gemini)      m=".gemini-proxy-on" ;;
      grok)        m=".grok-proxy-on" ;;
      *)           m=".$1-proxy-on" ;;
    esac
  fi
  print -r -- "$m"
}

_psw_effective_proxy() {
  local app="$1" marker murl
  marker="$(_psw_marker_name "$app")"
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

# --- 每工具三态模式: auto / proxy(强制代理) / direct(强制直连) ----------------
# 标记文件（$HOME 下，名字取自 config.json markers.<app>）：
#   <marker>(…-on)   -> 强制代理：总是注入；标记里存的地址失效时改用探测结果
#   <marker>-off 后缀 -> 强制直连：绝不注入
#   两者都无          -> 自动：启动时探测，代理存活才注入（无代理不报错，直连）
# 老版本标记里存的是 URL；empty 文件同样表示强制代理，_psw_effective_proxy
# 读不到 URL 会回落到探测，行为兼容。
_psw_off_marker_name() {   # $1=on-marker 名 -> 打印 off-marker 名
  local m="$1"
  if [[ "$m" == *on ]]; then
    print -r -- "${m%??}off"
  else
    print -r -- "${m}-off"
  fi
}

_psw_get_mode() {   # $1=app -> "proxy" | "direct" | "auto"
  local on off
  on="$(_psw_marker_name "$1")"
  if [[ -n "$on" && -f "$HOME/$on" ]]; then
    print -r -- proxy
    return 0
  fi
  off="$(_psw_off_marker_name "$on")"
  if [[ -n "$off" && -f "$HOME/$off" ]]; then
    print -r -- direct
    return 0
  fi
  print -r -- auto
}

_psw_set_mode() {   # $1=app $2=auto|proxy|direct
  local on off
  on="$(_psw_marker_name "$1")"
  off="$(_psw_off_marker_name "$on")"
  rm -f "$HOME/$on" "$HOME/$off"
  case "$2" in
    proxy)  [[ -n "$on"  ]] && : > "$HOME/$on" ;;
    direct) [[ -n "$off" ]] && : > "$HOME/$off" ;;
  esac
}

# 统一注入决策点（桌面启动 + CLI 包装共用）。设置全局：
#   _PSW_DECISION_MODE = auto|proxy|direct
#   _PSW_DECISION_URL  = 注入地址（直连时为空）
#   _PSW_DECISION_SRC  = 来源 (marker|config|system|probe|none)
# 返回 0 = 应注入代理环境；1 = 直连。
# 注意来源必须从返回行解析：_psw_resolve_alive/_psw_effective_proxy 在 $()
# 子 shell 里运行，它们对 _PSW_PROXY_SOURCE 的赋值不会传回父进程。
_psw_decide_injection() {
  local app="$1" mode line url src
  mode="$(_psw_get_mode "$app")"
  _PSW_DECISION_MODE="$mode"
  _PSW_DECISION_URL=""
  _PSW_DECISION_SRC="none"
  case "$mode" in
    direct)
      return 1
      ;;
    proxy)
      line="$(_psw_effective_proxy "$app")"
      ;;
    *)
      if ! line="$(_psw_resolve_alive)"; then
        return 1
      fi
      ;;
  esac
  url="${line%%|*}"
  if [[ -z "$url" ]]; then
    return 1
  fi
  src="${line##*|}"
  _PSW_DECISION_URL="$url"
  _PSW_DECISION_SRC="$src"
  _PSW_PROXY_SOURCE="$src"
  return 0
}

# Gemini.app 专有自愈与环境适配:
# 1) Gemini 内置的 libcurl (curl_api.cc) 在 proxy_config 为空时硬编码了
#    curl_easy_setopt(curl, CURLOPT_NOPROXY, "*")，导致其 OAuth token 刷新
#    强制直连并超时 (curl code 28)。将 '*\0' 热补丁为 '\0\0' 可解除该限制。
# 2) 检查 macOS 代理绕过列表，若包含错误的 '172.2*' 通配符（会导致
#    Google 的 172.217.* 被绕过直连），自动修正为标准的 172.20.*~172.29.*。
_psw_patch_gemini_if_needed() {
  local bin="$1"
  [[ -f "$bin" ]] || return 0
  [[ "$bin" == *"/Gemini" ]] || return 0

  # 1. 检测并修补二进制中硬编码的 CURLOPT_NOPROXY "*"
  python3 - "$bin" <<'PY' >/dev/null 2>&1 || true
import os, sys, subprocess

bin_path = sys.argv[1]
try:
    with open(bin_path, "r+b") as f:
        data = f.read()
        target = b"*\x00Unexpected error setting proxy"
        pos = data.find(target)
        if pos != -1:
            f.seek(pos)
            f.write(b"\x00\x00")
            f.flush()
            app_dir = bin_path
            while app_dir and not app_dir.endswith(".app"):
                app_dir = os.path.dirname(app_dir)
            if app_dir:
                subprocess.run(["codesign", "--force", "--deep", "-s", "-", app_dir],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except Exception:
    pass
PY

  # 2. 检查并修正 macOS 系统代理绕过列表中的 172.2* 通配符错误
  if command -v networksetup >/dev/null 2>&1; then
    local bypass
    bypass="$(networksetup -getproxybypassdomains "Wi-Fi" 2>/dev/null || true)"
    if [[ "$bypass" == *"172.2*"* ]]; then
      local fixed
      fixed="${bypass//172.2\*/172.20.* 172.21.* 172.22.* 172.23.* 172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.*}"
      # shellcheck disable=SC2086
      networksetup -setproxybypassdomains "Wi-Fi" $fixed >/dev/null 2>&1 || true
    fi
  fi
}

# Run a command with proxy env per the app's tri-state mode (see
# _psw_decide_injection). Prefix assignment only — does not export into the
# current shell. Prints a one-line decision note to stderr.
_psw_run_with_marker() {
  local app="$1"; shift
  if [[ ! -f "$PROXY_SWITCHER_CONFIG" ]]; then
    print -u2 "proxy-switcher: 找不到配置文件 $PROXY_SWITCHER_CONFIG"
    return 1
  fi
  local np
  np="$(_psw_no_proxy)"
  if _psw_decide_injection "$app"; then
    print -u2 "[proxy-switcher] ${_PSW_DECISION_MODE}: 走代理 $_PSW_DECISION_URL (来源: $_PSW_DECISION_SRC)"
    if [[ "$app" == "gemini" ]]; then
      local host_port="${_PSW_DECISION_URL#*://}"
      local socks_url="socks5://${host_port}"
      # shellcheck disable=SC2097,SC2098 # 有意同时注入大小写代理变量与 NO_PROXY/no_proxy
      HTTPS_PROXY="$socks_url" HTTP_PROXY="$socks_url" ALL_PROXY="$socks_url" \
      https_proxy="$socks_url" http_proxy="$socks_url" all_proxy="$socks_url" \
      GRPC_PROXY="$_PSW_DECISION_URL" grpc_proxy="$_PSW_DECISION_URL" \
      NO_PROXY="$np" no_proxy="$np" \
        "$@"
    else
      # shellcheck disable=SC2097,SC2098 # 有意同时注入大小写代理变量与 NO_PROXY/no_proxy
      HTTPS_PROXY="$_PSW_DECISION_URL" HTTP_PROXY="$_PSW_DECISION_URL" ALL_PROXY="$_PSW_DECISION_URL" \
      https_proxy="$_PSW_DECISION_URL" http_proxy="$_PSW_DECISION_URL" all_proxy="$_PSW_DECISION_URL" \
      NO_PROXY="$np" no_proxy="$np" \
        "$@"
    fi
  else
    case "$_PSW_DECISION_MODE" in
      direct) print -u2 "[proxy-switcher] 强制直连（不走代理）" ;;
      *)      print -u2 "[proxy-switcher] 自动: 未检测到可用代理，直连运行" ;;
    esac
    "$@"
  fi
}

# For desktop launch: drop inherited proxy vars, then inject per tri-state
# mode. Return 0 if injecting, 1 if starting direct. Exports into the current
# (short-lived launcher) process so the spawned app inherits them.
_psw_prepare_desktop_env() {
  local app="$1"
  local np
  np="$(_psw_no_proxy)"
  unset HTTPS_PROXY HTTP_PROXY ALL_PROXY https_proxy http_proxy all_proxy NO_PROXY no_proxy GRPC_PROXY grpc_proxy
  if _psw_decide_injection "$app"; then
    if [[ "$app" == "gemini" ]]; then
      local host_port="${_PSW_DECISION_URL#*://}"
      local socks_url="socks5://${host_port}"
      export HTTPS_PROXY="$socks_url" HTTP_PROXY="$socks_url" ALL_PROXY="$socks_url"
      export https_proxy="$socks_url" http_proxy="$socks_url" all_proxy="$socks_url"
      export GRPC_PROXY="$_PSW_DECISION_URL" grpc_proxy="$_PSW_DECISION_URL"
    else
      export HTTPS_PROXY="$_PSW_DECISION_URL" HTTP_PROXY="$_PSW_DECISION_URL" ALL_PROXY="$_PSW_DECISION_URL"
      export https_proxy="$_PSW_DECISION_URL" http_proxy="$_PSW_DECISION_URL" all_proxy="$_PSW_DECISION_URL"
    fi
    export NO_PROXY="$np" no_proxy="$np"
    return 0
  fi
  return 1
}
