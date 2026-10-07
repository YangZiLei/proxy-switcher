#!/bin/zsh
# shellcheck shell=bash
# ============================================================
# Launch Grok Build TUI with proxy injected
# ============================================================

SCRIPT_DIR="${0:A:h}"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/profile.zsh"

grok-proxy "$@"
