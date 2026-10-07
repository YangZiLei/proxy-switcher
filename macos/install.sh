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
#   ~/Applications/Gemini 代理启动.command
#
# 用法:
#   ./install.sh
#
# 可选：把 profile.zsh 挂进 ~/.zshrc（提供 opencode-proxy / agy-proxy / gemini-proxy）
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
   "$SRC_DIR/lib.zsh" "$SRC_DIR/open-menu.sh" "$SRC_DIR/run-grok.sh" "$DST_DIR/"
chmod +x "$DST_DIR/switcher.sh" "$DST_DIR/launch.sh" "$DST_DIR/open-menu.sh" "$DST_DIR/run-grok.sh"

if [[ -d "$SRC_DIR/assets/icons" ]]; then
  mkdir -p "$DST_DIR/icons"
  cp "$SRC_DIR/assets/icons"/*.icns "$SRC_DIR/assets/icons"/*.png "$DST_DIR/icons/" 2>/dev/null || true
  echo "   已复制应用包图标资源"
fi

if [[ ! -f "$DST_DIR/config.json" ]]; then
  cp "$SRC_DIR/config.example.json" "$DST_DIR/config.json"
  echo "   已生成 $DST_DIR/config.json（请按需修改代理地址）"
else
  echo "   已存在 config.json，跳过"
fi

echo "==> 2/3 生成双击启动器 (.app 原生应用 + .command 终端脚本)"
# 生成无界面的原生 .app Bundle（LSUIElement=true）：
# 双击直接由 LaunchServices 后台拉起，不触碰系统 Terminal.app，
# 也不会像 AppleScript applet 那样触发 TCC 权限弹窗。
write_app() { # $1=显示名 $2=要 exec 的命令 $3=图标名(可选)
  local name="$1"
  local cmd="$2"
  local icon_key="${3:-}"
  local app_dir="$APP_DIR/$name.app"
  local bin_dir="$app_dir/Contents/MacOS"
  local res_dir="$app_dir/Contents/Resources"
  local id_hash
  id_hash="$(print -n "$name" | shasum | awk '{print substr($1,1,8)}')"

  rm -rf "$app_dir"
  mkdir -p "$bin_dir" "$res_dir"

  local icon_plist=""
  if [[ -n "$icon_key" && -f "$DST_DIR/icons/$icon_key.icns" ]]; then
    cp "$DST_DIR/icons/$icon_key.icns" "$res_dir/AppIcon.icns"
    icon_plist="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
  fi

  cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>run</string>
$icon_plist
    <key>CFBundleIdentifier</key>
    <string>com.proxy-switcher.$id_hash</string>
    <key>CFBundleName</key>
    <string>$name</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

  cat > "$bin_dir/run" <<RUN
#!/bin/zsh
exec $cmd
RUN
  chmod +x "$bin_dir/run"

  # 刷新应用包时间戳，并注册到 LaunchServices
  touch "$app_dir"
  /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$app_dir" >/dev/null 2>&1 || true

  # 同时打上 Finder 专属图标（优先使用高速 fileicon，回退使用 swift）
  if [[ -n "$icon_key" ]]; then
    if command -v fileicon >/dev/null 2>&1 && [[ -f "$DST_DIR/icons/$icon_key.icns" ]]; then
      fileicon set "$app_dir" "$DST_DIR/icons/$icon_key.icns" >/dev/null 2>&1 || true
    elif [[ -f "$DST_DIR/icons/$icon_key.png" ]]; then
      swift - "$app_dir" "$DST_DIR/icons/$icon_key.png" <<'SWIFT' >/dev/null 2>&1 || true
import AppKit
let args = CommandLine.arguments
if args.count >= 3, let img = NSImage(contentsOfFile: args[2]) {
    NSWorkspace.shared.setIcon(img, forFile: args[1], options: [])
}
SWIFT
    fi
  fi

  echo "   ✓ $name.app (原生双击启动，内置专属图标)"
}

write_command() { # $1=显示名 $2=要 exec 的命令 $3=图标名(可选)
  local dest="$APP_DIR/$1.command"
  local icon_key="${3:-}"
  printf '#!/bin/zsh\nexec %s\n' "$2" > "$dest"
  chmod +x "$dest"
  if [[ -n "$icon_key" ]]; then
    if command -v fileicon >/dev/null 2>&1 && [[ -f "$DST_DIR/icons/$icon_key.icns" ]]; then
      fileicon set "$dest" "$DST_DIR/icons/$icon_key.icns" >/dev/null 2>&1 || true
    elif [[ -f "$DST_DIR/icons/$icon_key.png" ]]; then
      swift - "$dest" "$DST_DIR/icons/$icon_key.png" <<'SWIFT' >/dev/null 2>&1 || true
import AppKit
let args = CommandLine.arguments
if args.count >= 3, let img = NSImage(contentsOfFile: args[2]) {
    NSWorkspace.shared.setIcon(img, forFile: args[1], options: [])
}
SWIFT
    fi
  fi
  echo "   ✓ $1.command"
}

# 1. 生成 .app 原生应用包（首选：双击无终端弹窗，直接拉起目标终端或静默启动）
write_app "代理切换" "\"$DST_DIR/open-menu.sh\"" "proxy"
write_app "OpenCode 代理启动" "\"$DST_DIR/launch.sh\" -q opencode" "opencode"
write_app "Antigravity 代理启动" "\"$DST_DIR/launch.sh\" -q antigravity" "antigravity"
write_app "Gemini 代理启动" "\"$DST_DIR/launch.sh\" -q gemini" "gemini"
write_app "Grok 代理启动" "\"$DST_DIR/open-menu.sh\" \"$DST_DIR/run-grok.sh\"" "grok"

# 2. 生成 .command 兼容脚本
write_command "代理切换" "\"$DST_DIR/open-menu.sh\"" "proxy"
write_command "OpenCode 代理启动" "\"$DST_DIR/launch.sh\" -q opencode" "opencode"
write_command "Antigravity 代理启动" "\"$DST_DIR/launch.sh\" -q antigravity" "antigravity"
write_command "Gemini 代理启动" "\"$DST_DIR/launch.sh\" -q gemini" "gemini"
write_command "Grok 代理启动" "\"$DST_DIR/open-menu.sh\" \"$DST_DIR/run-grok.sh\"" "grok"

echo "==> 3/3 ${1:+挂载 zsh 函数}"
if [[ "$1" == "--with-zshrc" ]]; then
  line=". \"\$HOME/.config/proxy-switcher/profile.zsh\""
  if ! grep -qF "$HOME/.config/proxy-switcher/profile.zsh" "$HOME/.zshrc" 2>/dev/null; then
    printf '\n# proxy-switcher: per-tool proxy injection (opencode-proxy / agy-proxy / gemini-proxy / grok-proxy)\n%s\n' "$line" >> "$HOME/.zshrc"
    echo "   ✓ 已追加到 ~/.zshrc（新开终端生效）"
  else
    echo "   ~/.zshrc 已包含，跳过"
  fi
else
  echo "   未挂载 .zshrc（如需 CLI 函数: ./install.sh --with-zshrc）"
fi

# 刷新 Finder 图标缓存
killall Finder 2>/dev/null || true
qlmanage -r cache 2>/dev/null || true
qlmanage -r 2>/dev/null || true

echo ""
echo "部署完成！"
echo "  - 菜单（推荐）：双击 $APP_DIR/代理切换.app（直接拉起 Ghostty，零多余终端，可按键选择启动各应用）"
echo "  - 桌面独立启动：双击 $APP_DIR/Antigravity 代理启动.app / Gemini 代理启动.app / OpenCode 代理启动.app / Grok 代理启动.app"
echo "    （原生后台静默注入启动桌面端，Grok 直接拉起终端 TUI，顶部通知栏反馈结果）"
echo "  - 终端命令：在 Ghostty / 终端里直接输入 proxy-switch 或 psw 即可随时呼出菜单"
echo "  - CLI 函数：opencode-proxy / agy-proxy / gemini-proxy / grok-proxy"
echo "  - 兼容脚本：$APP_DIR/*.command"
echo "  - 启动日志：$DST_DIR/launch.log"
echo "  - 配置文件：$DST_DIR/config.json"