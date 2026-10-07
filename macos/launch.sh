#!/bin/zsh
# shellcheck shell=bash
# ============================================================
# proxy-switcher — macOS 桌面端启动器
# 按三态模式注入代理环境变量后启动桌面应用 (OpenCode / Antigravity)
#
# 用法:
#   launch.sh <opencode|antigravity>          # 前台，详细输出（主菜单调用）
#   launch.sh -q <opencode|antigravity>       # 静默：校验后转后台执行并立即
#                                             # 退出（.command 双击用）。结果经
#                                             # macOS 通知反馈，过程写入日志
#   launch.sh --worker <app>                  # 内部：后台执行体（输出已在父进程
#                                             # 重定向到 launch.log），勿手工调用
#
# 注入模式（三态，标记文件在 $HOME，名字取自 config.json markers.<app>）:
#   强制代理 (…-on)  -> 总是注入；地址失效时自动改用探测结果
#   强制直连 (…-off) -> 绝不注入
#   自动 (无标记)    -> 启动时探测：代理存活则注入并通知，否则直连并通知
#
# 要点:
#   * macOS 的 `open -a` 不传递环境变量，所以这里直接启动 bundle 内的二进制，
#     让 Electron 及其 spawn 的 language_server / Node 服务继承注入的 env。
#   * Electron 是单实例：二次启动的 env 会被转发给旧实例后退出，所以只要
#     应用已在运行（无论何种模式）都先杀掉旧实例，再按当前模式启动。
#   * 只注入 HTTPS_PROXY/HTTP_PROXY/ALL_PROXY + NO_PROXY，不触碰全局环境变量。
# ============================================================

: "${PROXY_SWITCHER_CONFIG:=$HOME/.config/proxy-switcher/config.json}"
SCRIPT_DIR="${0:A:h}"
# shellcheck disable=SC1091
# shellcheck source=lib.zsh
. "$SCRIPT_DIR/lib.zsh"
# 经 .command 双击拉起时环境变量可能不完整，先补齐 PATH（lsof 用于白屏恢复）
_psw_prepare_path

LOG_DIR="${PROXY_SWITCHER_CONFIG:h}"
LOG_FILE="$LOG_DIR/launch.log"

usage() { print -u2 "用法: launch.sh [-q|--quiet] <opencode|antigravity|gemini|...>"; exit 1; }

QUIET=0
WORKER=0
APP=""
while (( $# )); do
  case "$1" in
    -q|--quiet) QUIET=1; shift ;;
    --worker)   WORKER=1; shift ;;
    -*) usage ;;
    *)
      [[ -z "$APP" ]] || usage
      APP="$1"; shift ;;
  esac
done
[[ -n "$APP" ]] || usage

# 白屏自动恢复：LS(Go) 启动要 ~37s(playwright 404 重试+网络初始化)，
# Electron 窗口过早加载 → 30s 超时 → 白屏定格。此函数：
#   1. 轮询 language_server 的 HTTPS 端口直到 HTTP 200
#   2. 经 CDP (remote-debugging-port) 重载窗口
# 成功时置 _PSW_RECOVER_OK=1（其余路径保持 0），供通知汇报结果。
_psw_recover_white_screen() {
  local app_name="$1"
  _PSW_RECOVER_OK=0
  command -v node >/dev/null 2>&1 || { print -u2 "警告: 未找到 node，无法经 CDP 自动重载窗口。白屏时请手动 Cmd+R。安装 Node ≥ 21 后即可自动恢复。"; return 0; }
  # 全局 WebSocket 需 Node >= 21（22 稳定）。旧版会 ReferenceError 静默失败，
  # 提前检测，避免恢复逻辑空转 ~90s 后才提示。
  if ! node -e 'process.exit(typeof WebSocket === "function" ? 0 : 1)' >/dev/null 2>&1; then
    print -u2 "警告: 白屏自动恢复需要 Node ≥ 21（CDP WebSocket），当前 $(node --version 2>/dev/null || echo 未知)。跳过自动恢复，白屏时请手动 Cmd+R。"
    return 0
  fi

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

  # 找到窗口 target：优先主窗口(https://127.0.0.1:)，否则 splash(data:) 也可用于导航
  # 白屏判定：主窗口标题 = "127.0.0.1:<port>" 或空；真实标题如 Antigravity = 已加载
  local attempt
  for (( attempt = 0; attempt < 12; attempt++ )); do
    local pages_json
    pages_json=$(curl -s "http://127.0.0.1:$dp/json/list" 2>/dev/null)
    [[ -z "$pages_json" || "$pages_json" == "[]" ]] && { sleep 6; continue; }

    # 1) 尝试找主窗口（https://127.0.0.1:）
    local tgt="" title=""
    tgt=$(echo "$pages_json" | python3 -c "
import sys, json
try:
    for t in json.load(sys.stdin):
        if t.get('type')=='page' and t.get('url','').startswith('https://127.0.0.1:'):
            print(t.get('webSocketDebuggerUrl','')+'||'+t.get('title','')+'||'+t.get('url',''))
            break
except Exception:
    pass" 2>/dev/null)
    if [[ -n "$tgt" ]]; then
      title="${tgt#*||}"; title="${title%%||*}"
      if [[ "$title" != "127.0.0.1:"* && -n "$title" ]]; then
        print "白屏恢复完成（窗口已加载: $title）"
        _PSW_RECOVER_OK=1
        return 0
      fi
      # 白屏：重载当前 URL
      node -e '
const ws = new WebSocket(process.argv[1]);
const t = setTimeout(()=>process.exit(0), 4000);
ws.onopen = () => { ws.send(JSON.stringify({id:1,method:"Page.reload",params:{ignoreCache:true}})); setTimeout(()=>{clearTimeout(t);process.exit(0)},800); };
ws.onerror = () => { clearTimeout(t); process.exit(1); };
' "${tgt%%||*}" >/dev/null 2>&1
      sleep 6
      continue
    fi

    # 2) 未找到主窗口，可能还在 splash(data:) → 导航到 LS URL
    local splash_ws=""
    splash_ws=$(echo "$pages_json" | python3 -c "
import sys, json
try:
    for t in json.load(sys.stdin):
        if t.get('type')=='page':
            print(t.get('webSocketDebuggerUrl',''))
            break
except Exception:
    pass" 2>/dev/null)
    if [[ -n "$splash_ws" && -n "$lsport" ]]; then
      node -e '
const ws = new WebSocket(process.argv[1]);
const url = process.argv[2];
const t = setTimeout(()=>process.exit(0), 4000);
ws.onopen = () => { ws.send(JSON.stringify({id:1,method:"Page.navigate",params:{url}})); setTimeout(()=>{clearTimeout(t);process.exit(0)},800); };
ws.onerror = () => { clearTimeout(t); process.exit(1); };
' "$splash_ws" "https://127.0.0.1:$lsport/" >/dev/null 2>&1
      sleep 6
      continue
    fi
    sleep 6
  done
  print -u2 "警告: 重载多次仍未加载，请手动 Cmd+R 恢复"
  return 0
}

# --- 公共校验（三条路径共用）------------------------------------------------
[[ -f "$PROXY_SWITCHER_CONFIG" ]] || {
  print -u2 "错误：找不到配置文件 $PROXY_SWITCHER_CONFIG"
  _psw_notify "proxy-switcher" "启动失败：找不到配置文件 $PROXY_SWITCHER_CONFIG" "sound"
  exit 1
}

desktop="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.$APP.desktop")"
chromium_args="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.$APP.chromiumArgs")"
recover_flag="$(_psw_config_get "$PROXY_SWITCHER_CONFIG" "apps.$APP.recoverWhiteScreen")"

if [[ -z "$desktop" || ! -f "$desktop" ]]; then
  case "$APP" in
    gemini)
      if [[ -f "/Applications/Gemini.app/Contents/MacOS/Gemini" ]]; then
        desktop="/Applications/Gemini.app/Contents/MacOS/Gemini"
      elif [[ -f "$HOME/Applications/Gemini.app/Contents/MacOS/Gemini" ]]; then
        desktop="$HOME/Applications/Gemini.app/Contents/MacOS/Gemini"
      fi
      ;;
    opencode)
      if [[ -f "/Applications/OpenCode.app/Contents/MacOS/OpenCode" ]]; then
        desktop="/Applications/OpenCode.app/Contents/MacOS/OpenCode"
      elif [[ -f "$HOME/Applications/OpenCode.app/Contents/MacOS/OpenCode" ]]; then
        desktop="$HOME/Applications/OpenCode.app/Contents/MacOS/OpenCode"
      fi
      ;;
    antigravity)
      if [[ -f "/Applications/Antigravity.app/Contents/MacOS/Antigravity" ]]; then
        desktop="/Applications/Antigravity.app/Contents/MacOS/Antigravity"
      elif [[ -f "$HOME/Applications/Antigravity.app/Contents/MacOS/Antigravity" ]]; then
        desktop="$HOME/Applications/Antigravity.app/Contents/MacOS/Antigravity"
      fi
      ;;
  esac
fi

[[ -n "$desktop" && -f "$desktop" ]] || {
  print -u2 "错误：找不到桌面端应用: $desktop"
  _psw_notify "proxy-switcher" "启动失败：找不到桌面端应用 $desktop" "sound"
  exit 1
}

BIN_NAME="${desktop:t}"   # 二进制文件名 (OpenCode / Antigravity / Gemini)
# macOS 经 LaunchServices 启动的 GUI app：内核 comm 被截断成 16 字符
# （如 "/Applications/Op"），pgrep 按 name/comm/argv 均不可靠。
# 改用 ps -axo args=（完整 argv）按可执行文件路径精确匹配主进程（兼容带空格路径）。
main_pid() {
  ps -axo pid=,args= | awk -v p="$desktop" '{
    pid = $1
    sub(/^[ \t]*[0-9]+[ \t]+/, "")
    if ($0 == p || substr($0, 1, length(p) + 1) == p " ") {
      print pid
      exit
    }
  }'
}
is_running() { [[ -n "$(main_pid)" ]]; }
kill_main()  {
  local p
  p="$(main_pid)"
  [[ -n "$p" ]] && kill "$p" >/dev/null 2>&1
  # 若该应用为 .app bundle，同时清理同 bundle 下拉起的辅助/后台守护进程（如 GeminiAppLauncher）
  if [[ "$desktop" == *"/Contents/"* ]]; then
    local app_bundle="${desktop%/Contents/*}"
    if [[ -d "$app_bundle" && "$app_bundle" != "/" ]]; then
      pkill -f "$app_bundle/" >/dev/null 2>&1 || true
    fi
  fi
}

# 单实例锁：无论模式如何，只要旧实例还在，就先退出再拉起，否则二次启动会把
# 请求转发给旧进程（其 env 可能与当前模式不一致）。Electron/原生应用优雅退出
# 最长可拖 ~5s，必须在旧进程完全消失后再启动。
kill_old_instance() {
  if is_running; then
    print "正在退出旧实例 $BIN_NAME（使当前代理模式生效）..."
    kill_main
    local waited=0
    while is_running && (( waited < 12 )); do sleep 1; ((waited++)); done
    if is_running; then
      print "旧实例未及时退出，强制结束..."
      local op
      op="$(main_pid)"
      [[ -n "$op" ]] && kill -9 "$op" >/dev/null 2>&1
      if [[ "$desktop" == *"/Contents/"* ]]; then
        local app_bundle="${desktop%/Contents/*}"
        [[ -d "$app_bundle" && "$app_bundle" != "/" ]] && pkill -9 -f "$app_bundle/" >/dev/null 2>&1 || true
      fi
      sleep 1
    fi
  fi
}

# 按 Chromium 参数拆分 + 注入决策，后台拉起桌面端并返回是否成功
spawn_app() {
  local -a chrome=()
  # ${=var} 是 zsh 显式按词拆分语法(等价 bash 未加引号展开)
  # shellcheck disable=SC2206
  [[ -n "$chromium_args" ]] && chrome=(${=chromium_args})
  nohup "$desktop" "${chrome[@]}" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  sleep 2
  is_running
}

# --- worker：后台执行体（quiet 模式的实际工作进程）---------------------------
worker_main() {
  print "============================================================"
  print "== $(date '+%F %T') launch $APP (worker) =="

  kill_old_instance

  if [[ "$APP" == "gemini" ]]; then
    _psw_patch_gemini_if_needed "$desktop"
  fi

  if _psw_prepare_desktop_env "$APP"; then
    print "注入代理: $HTTPS_PROXY (来源: $_PSW_PROXY_SOURCE, 模式: $_PSW_DECISION_MODE)"
  else
    print "直连启动 (模式: $_PSW_DECISION_MODE)"
  fi
  local proxy_txt="直连"
  [[ -n "$HTTPS_PROXY" ]] && proxy_txt="走代理 $HTTPS_PROXY"

  if ! spawn_app; then
    print -u2 "错误：$BIN_NAME 启动失败或立即退出"
    _psw_notify "$BIN_NAME" "启动失败，详见 launch.log" "sound"
    return 1
  fi
  print "已启动 $BIN_NAME (pid $(main_pid))"

  # 白屏自动恢复：等 LS 就绪后经 CDP 重载窗口；结果经通知汇报
  if [[ "$recover_flag" == "true" ]]; then
    _psw_recover_white_screen "$BIN_NAME"
    if (( _PSW_RECOVER_OK )); then
      _psw_notify "$BIN_NAME" "已就绪 · $proxy_txt"
    else
      _psw_notify "$BIN_NAME" "已启动，但白屏自动恢复未完成 — 若白屏请手动 Cmd+R（详见 launch.log）" "sound"
    fi
  else
    _psw_notify "$BIN_NAME" "已启动 · $proxy_txt"
  fi
  return 0
}

if (( WORKER )); then
  worker_main "$APP"
  exit $?
fi

# --- quiet：校验后转后台，立即退出（.command 双击路径）------------------------
if (( QUIET )); then
  # 日志超 256KB 轮转，避免无限增长
  if [[ -f "$LOG_FILE" ]] && (( $(wc -c < "$LOG_FILE" 2>/dev/null || print 0) > 262144 )); then
    mv -f "$LOG_FILE" "$LOG_FILE.1"
  fi
  _qmode_txt=""
  case "$(_psw_get_mode "$APP")" in
    proxy)  _qmode_txt="强制代理" ;;
    direct) _qmode_txt="强制直连" ;;
    *)      _qmode_txt="自动探测" ;;
  esac
  print "已在后台启动 $BIN_NAME (代理模式: $_qmode_txt)，结果见 macOS 通知；日志: $LOG_FILE"
  _psw_notify "$BIN_NAME" "后台启动中（代理模式: $_qmode_txt）..."
  nohup zsh "$SCRIPT_DIR/launch.sh" --worker "$APP" >>"$LOG_FILE" 2>&1 &
  disown 2>/dev/null || true
  exit 0
fi

# --- 前台详细模式（主菜单 [5]/[6] 路径）---------------------------------------
kill_old_instance

if [[ "$APP" == "gemini" ]]; then
  _psw_patch_gemini_if_needed "$desktop"
fi

if _psw_prepare_desktop_env "$APP"; then
  print "注入代理: $HTTPS_PROXY (来源: $_PSW_PROXY_SOURCE, 模式: $_PSW_DECISION_MODE)"
else
  print "直连启动 (模式: $_PSW_DECISION_MODE)"
fi

# 后台启动桌面端（继承当前 shell 的环境变量）。chromiumArgs（如
# --no-proxy-server）用于规避系统 PAC 劫持 Chromium 的回环代理解析
# （Antigravity 白屏问题）；需按词拆分传参。
if ! spawn_app; then
  print -u2 "警告：$BIN_NAME 启动失败或立即退出"
  exit 1
fi
print "已启动 $BIN_NAME (pid $(main_pid))"

# 白屏自动恢复：language_server 启动要 ~37s(playwright 404 重试等)，
# 窗口过早加载会在 30s 超时后定格白屏。等 LS 就绪后经 CDP 重载窗口。
if [[ "$recover_flag" == "true" ]]; then
  _psw_recover_white_screen "$BIN_NAME"
fi
