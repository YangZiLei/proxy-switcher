#!/bin/zsh
# shellcheck shell=bash
# ============================================================
# Open switcher.sh in an available terminal (runtime detection).
# Order: PROXY_SWITCHER_TERMINAL override, Ghostty, iTerm, Kitty, Terminal.app.
# ============================================================

set -e
SCRIPT_DIR="${0:A:h}"
TARGET="${1:-$SCRIPT_DIR/switcher.sh}"

fail() {
  local msg="$1"
  print -u2 "$msg"
  local escaped="${msg//\"/\\\"}"
  osascript -e "display dialog \"$escaped\" buttons {\"OK\"} default button 1 with title \"proxy-switcher\" with icon stop" >/dev/null 2>&1 || true
  exit 1
}

[[ -x "$TARGET" ]] || fail "找不到脚本：$TARGET。请重新运行 macos/install.sh"

app_exists() {
  local name="$1"
  [[ -d "/Applications/${name}.app" || -d "$HOME/Applications/${name}.app" || -d "/System/Applications/${name}.app" || -d "/System/Applications/Utilities/${name}.app" ]]
}

run_open() {
  # "$@" is an `open` argv. Fail visibly if LaunchServices rejects it.
  if ! open "$@"; then
    fail "无法打开终端。请自行运行：$TARGET"
  fi
}

if [[ -n "${PROXY_SWITCHER_TERMINAL:-}" ]]; then
  if [[ -x "$PROXY_SWITCHER_TERMINAL" ]]; then
    "$PROXY_SWITCHER_TERMINAL" -e "$TARGET" &
    exit 0
  fi
  run_open -na "$PROXY_SWITCHER_TERMINAL" --args -e "$TARGET"
  exit 0
fi

if app_exists Ghostty; then
  run_open -na Ghostty --args -e "$TARGET"
elif app_exists iTerm; then
  run_open -na iTerm "$TARGET"
elif app_exists kitty; then
  run_open -na kitty --args -e "$TARGET"
elif app_exists Terminal; then
  run_open -a Terminal "$TARGET"
else
  fail "未找到可用终端（Ghostty / iTerm / Kitty / Terminal.app）。请自行运行：$TARGET"
fi
