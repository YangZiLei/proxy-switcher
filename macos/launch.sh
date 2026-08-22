#!/bin/zsh
# ============================================================
# proxy-switcher — macOS 桌面端启动器
# 按标记注入代理环境变量后启动桌面应用 (OpenCode / Antigravity)
#
# 用法:
#   launch.sh opencode
#   launch.sh antigravity
#
# 要点:
#   * macOS 的 `open -a` 不传递环境变量，所以这里直接启动
#     bundle 内的二进制，让 Electron 及其 spawn 的
#     language_server / Node 服务继承注入的 env。
#   * Electron 是单实例：二次启动的 env 会被转发给旧实例后退出，
#     所以标记开启时先杀掉旧实例，强制新进程继承新环境。
#   * 只注入 HTTPS_PROXY/HTTP_PROXY/ALL_PROXY + NO_PROXY，
#     不触碰全局环境变量。
# ============================================================

: "${PROXY_SWITCHER_CONFIG:=$HOME/.config/proxy-switcher/config.json}"

# 白屏自动恢复：LS(Go) 启动要 ~37s(playwright 404 重试+网络初始化)，
# Electron 窗口过早加载 → 30s 超时 → 白屏定格。此函数：
#   1. 轮询 language_server 的 HTTPS 端口直到 HTTP 200
#   2. 经 CDP (remote-debugging-port) 重载窗口
_psw_recover_white_screen() {
  local app_name="$1"
  command -v node >/dev/null 2>&1 || { print -u2 "警告: 未找到 node，跳过白屏自动恢复（可手动 Cmd+R）"; return 0; }

  local lsport=""
  local i
  for (( i = 0; i < 45; i++ )); do
    lsport=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '$1 ~ /^language/ {n=split($9,a,":"); print a[n]; exit}')
    [[ -n "$lsport" ]] && break
    sleep 2
  done
  [[ -z "$lsport" ]] && { print -u2 "警告: 未找到 language_server 端口，跳过白屏恢复"; return 0; }

  local code=""
  for (( i = 0; i < 45; i++ )); do
    code=$(curl -k --noproxy '*' -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 4 "https://127.0.0.1:$lsport/" 2>/dev/null)
    [[ "$code" == "200" ]] && break
    sleep 2
  done
  [[ "$code" != "200" ]] && { print -u2 "警告: language_server 未就绪($code)，白屏可能仍在"; return 0; }

  local dp=""
  dp=$(head -1 "$HOME/Library/Application Support/$app_name/DevToolsActivePort" 2>/dev/null | tr -d ' ')
  [[ -z "$dp" ]] && { print -u2 "警告: 未找到 DevTools 端口，请手动 Cmd+R 恢复"; return 0; }

  # 找到主窗口 target（URL 以 https://127.0.0.1: 开头），排除 splash(data:)
  # 标题 = "127.0.0.1:<port>" 或空 = 白屏；标题为真实值(如 Antigravity/onboarding) = 已加载
  local attempt
  local tgt=""
  local title=""
  for (( attempt = 0; attempt < 12; attempt++ )); do
    tgt=$(curl -s "http://127.0.0.1:$dp/json/list" 2>/dev/null | python3 -c "
import sys, json
try:
    for t in json.load(sys.stdin):
        if t.get('type')=='page' and t.get('url','').startswith('https://127.0.0.1:'):
            print(t.get('webSocketDebuggerUrl','')+'||'+t.get('title',''))
            break
except Exception:
    pass" 2>/dev/null)
    [[ -z "$tgt" ]] && { print -u2 "警告: 未找到主窗口 target，请手动 Cmd+R 恢复"; return 0; }
    title="${tgt#*||}"
    if [[ "$title" != "127.0.0.1:"* && -n "$title" ]]; then
      print "白屏恢复完成（窗口已加载: $title）"
      return 0
    fi

    node -e '
const ws = new WebSocket(process.argv[1]);
const t = setTimeout(()=>process.exit(0), 4000);
ws.onopen = () => { ws.send(JSON.stringify({id:1,method:"Page.reload",params:{ignoreCache:true}})); setTimeout(()=>{clearTimeout(t);process.exit(0)},800); };
ws.onerror = () => { clearTimeout(t); process.exit(1); };
' "${tgt%%||*}" >/dev/null 2>&1
    sleep 6
  done
  print -u2 "警告: 重载多次仍未加载，请手动 Cmd+R 恢复"
  return 0
}

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

APP="$1"
[[ -n "$APP" && ( "$APP" == "opencode" || "$APP" == "antigravity" ) ]] || {
  print -u2 "用法: launch.sh <opencode|antigravity>"
  exit 1
}

[[ -f "$PROXY_SWITCHER_CONFIG" ]] || {
  print -u2 "错误：找不到配置文件 $PROXY_SWITCHER_CONFIG"
  exit 1
}

proxy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "proxy.url")"
no_proxy="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "no_proxy")"
[[ -z "$no_proxy" ]] && no_proxy="127.0.0.1,localhost"
marker="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "markers.$APP")"
desktop="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.$APP.desktop")"
chromium_args="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.$APP.chromiumArgs")"

[[ -n "$desktop" && -f "$desktop" ]] || {
  print -u2 "错误：找不到桌面端应用: $desktop"
  exit 1
}

BIN_NAME="${desktop:t}"   # 二进制文件名 (OpenCode / Antigravity)
# macOS 经 LaunchServices 启动的 GUI app：内核 comm 被截断成 16 字符
# （如 "/Applications/Op"），pgrep 按 name/comm/argv 均不可靠。
# 改用 ps -axo args=（完整 argv）按 argv[0] 精确匹配主进程。
main_pid() { ps -axo pid=,args= | awk -v p="$desktop" '$2==p {print $1; exit}'; }
is_running() { [[ -n "$(main_pid)" ]]; }
kill_main()  { local p; p="$(main_pid)"; [[ -n "$p" ]] && kill "$p" >/dev/null 2>&1; }

if [[ -n "$marker" && -f "$HOME/$marker" ]]; then
  print "标记开启，注入代理: $proxy"
  # 单实例锁：先彻底退出旧实例，确保新进程继承新环境。
  # Electron 优雅退出最长可拖 ~5s（含 LS 关闭），必须在旧进程
  # 完全消失后再启动，否则新实例会转发给旧实例然后自己退出。
  if is_running; then
    print "正在退出旧实例 $BIN_NAME ..."
    kill_main
    local waited=0
    while is_running && (( waited < 12 )); do sleep 1; ((waited++)); done
    if is_running; then
      print "旧实例未及时退出，强制结束..."
      local op; op="$(main_pid)"
      [[ -n "$op" ]] && kill -9 "$op" >/dev/null 2>&1
      sleep 1
    fi
  fi
  export HTTPS_PROXY="$proxy" HTTP_PROXY="$proxy" ALL_PROXY="$proxy"
  export NO_PROXY="$no_proxy" no_proxy="$no_proxy"
else
  print "标记关闭，直连启动（未注入代理）"
  if is_running; then
    print "已在运行（直连），激活现有实例。"
    /usr/bin/open -a "$BIN_NAME" >/dev/null 2>&1
    exit 0
  fi
fi

# 后台启动桌面端（继承当前 shell 的环境变量）。
# chromiumArgs（如 --no-proxy-server）用于规避系统 PAC 劫持 Chromium
# 的回环代理解析（Antigravity 白屏问题）；需按词拆分传参。
local -a chrome=()
[[ -n "$chromium_args" ]] && chrome=(${=chromium_args})
nohup "$desktop" "${chrome[@]}" >/dev/null 2>&1 &
disown 2>/dev/null || true
sleep 2
if is_running; then
  print "已启动 $BIN_NAME (pid $(main_pid))"
else
  print -u2 "警告：$BIN_NAME 启动失败或立即退出"
  exit 1
fi

# 白屏自动恢复：language_server 启动要 ~37s(playwright 404 重试等)，
# 窗口过早加载会在 30s 超时后定格白屏。等 LS 就绪后经 CDP 重载窗口。
recover_flag="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.$APP.recoverWhiteScreen")"
if [[ "$recover_flag" == "true" ]]; then
  _psw_recover_white_screen "$BIN_NAME"
fi