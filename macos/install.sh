#!/bin/zsh
# shellcheck shell=bash
# ============================================================
# proxy-switcher for macOS — installer
#
# 一键部署到 ~/.config/proxy-switcher/ 并生成双击启动器（.command 文件，
# 以终端身份运行，不会触发 applet 的 TCC 授权弹窗）：
#   ~/Applications/代理切换.command           (检测终端打开主菜单)
#   ~/Applications/OpenCode 代理启动.command
#   ~/Applications/Antigravity 代理启动.command
#
# 用法:
#   ./install.sh
#
# 可选：把 profile.zsh 挂进 ~/.zshrc（提供 opencode-proxy / agy-proxy）
#   ./install.sh --with-zshrc
# ============================================================

set -e
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DST_DIR="$HOME/.config/proxy-switcher"
APP_DIR="$HOME/Applications"

[[ -d "$APP_DIR" ]] || mkdir -p "$APP_DIR"

echo "==> 1/3 复制脚本到 $DST_DIR"
mkdir -p "$DST_DIR"
cp "$SRC_DIR/switcher.sh" "$SRC_DIR/launch.sh" "$SRC_DIR/profile.zsh" \
   "$SRC_DIR/lib.zsh" "$SRC_DIR/open-menu.sh" "$DST_DIR/"
chmod +x "$DST_DIR/switcher.sh" "$DST_DIR/launch.sh" "$DST_DIR/open-menu.sh"

if [[ ! -f "$DST_DIR/config.json" ]]; then
  cp "$SRC_DIR/config.example.json" "$DST_DIR/config.json"
  echo "   已生成 $DST_DIR/config.json（请按需修改代理地址）"
else
  echo "   已存在 config.json，跳过"
fi

echo "==> 2/3 生成双击启动器 (.command，以终端身份运行)"
# .command 双击后由终端直接执行，不经过 AppleScript applet，
# 因此不会产生 applet 的 TCC（下载/图片等）授权弹窗。
# 旧版残留的 .app applet 如存在则删除，避免混淆。
write_command() { # $1=显示名 $2=要 exec 的命令（单行 shell）
  local dest="$APP_DIR/$1.command"
  rm -rf "$APP_DIR/$1.app"
  printf '#!/bin/zsh\nexec %s\n' "$2" > "$dest"
  chmod +x "$dest"
  echo "   ✓ $1.command"
}
write_command "代理切换" "\"$DST_DIR/open-menu.sh\""
write_command "OpenCode 代理启动" "\"$DST_DIR/launch.sh\" opencode"
write_command "Antigravity 代理启动" "\"$DST_DIR/launch.sh\" antigravity"

echo "==> 3/3 ${1:+挂载 zsh 函数}"
if [[ "$1" == "--with-zshrc" ]]; then
  line=". \"\$HOME/.config/proxy-switcher/profile.zsh\""
  if ! grep -qF "$HOME/.config/proxy-switcher/profile.zsh" "$HOME/.zshrc" 2>/dev/null; then
    printf '\n# proxy-switcher: per-tool proxy injection (opencode-proxy / agy-proxy)\n%s\n' "$line" >> "$HOME/.zshrc"
    echo "   ✓ 已追加到 ~/.zshrc（新开终端生效）"
  else
    echo "   ~/.zshrc 已包含，跳过"
  fi
else
  echo "   未挂载 .zshrc（如需 CLI 函数: ./install.sh --with-zshrc）"
fi

echo ""
echo "部署完成！"
echo "  - 菜单：双击 $APP_DIR/代理切换.command（或终端跑 $DST_DIR/switcher.sh）"
echo "  - 桌面端：双击 $APP_DIR/OpenCode 代理启动.command / Antigravity 代理启动.command"
echo "  - CLI：新终端里用 opencode-proxy / agy-proxy"
echo "  - 配置文件：$DST_DIR/config.json"