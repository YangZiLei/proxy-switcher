#!/bin/zsh
# shellcheck shell=bash
# ============================================================
# proxy-switcher for macOS — installer
#
# 一键部署到 ~/.config/proxy-switcher/ 并生成双击启动器：
#   ~/Applications/代理切换.app           (检测终端打开主菜单)
#   ~/Applications/OpenCode 代理启动.app
#   ~/Applications/Antigravity 代理启动.app
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

echo "==> 1/4 复制脚本到 $DST_DIR"
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

echo "==> 2/4 生成图标 (Swift/AppKit)"
# 生成 1024x1024 图标 → iconset → icns；失败则跳过（用默认图标）
gen_icns() { # $1=app 名 $2=文字 $3=文字颜色hex 梯度
  local out="/tmp/psw-icon-$1.icns" tmp="/tmp/psw-icon-$1"
  local swift="/tmp/psw-icon-$1.swift"
  cat > "$swift" <<EOF
import AppKit
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: S, height: S), xRadius: 200, yRadius: 200)
let c1 = NSColor(calibratedRed: $3, green: $4, blue: $5, alpha: 1)
let c2 = NSColor(calibratedRed: $6, green: $7, blue: $8, alpha: 1)
NSGradient(colors: [c1, c2])!.draw(in: bg, angle: -45)
let big = NSAttributedString(string: "$2", attributes: [
    .font: NSFont.systemFont(ofSize: 300, weight: .heavy),
    .foregroundColor: NSColor.white
])
let bs = big.size()
big.draw(at: NSPoint(x: (S - bs.width)/2, y: S/2 + 20))
let sub = NSAttributedString(string: "proxy 代理", attributes: [
    .font: NSFont.systemFont(ofSize: 74, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.9)
])
let ss = sub.size()
sub.draw(at: NSPoint(x: (S - ss.width)/2, y: S/2 - 30 - ss.height))
img.unlockFocus()
guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError() }
try! png.write(to: URL(fileURLWithPath: "$tmp.png"))
EOF
  if command -v swift >/dev/null 2>&1; then
    swift "$swift" >/dev/null 2>&1 || return 1
    rm -rf "$tmp.iconset"; mkdir -p "$tmp.iconset"
    for s in 16 32 128 256 512; do
      sips -z $s $s "$tmp.png" --out "$tmp.iconset/icon_${s}x${s}.png" >/dev/null 2>&1
      sips -z $((s*2)) $((s*2)) "$tmp.png" --out "$tmp.iconset/icon_${s}x${s}@2x.png" >/dev/null 2>&1
    done
    iconutil -c icns "$tmp.iconset" -o "$out" >/dev/null 2>&1
    rm -rf "$tmp" "$tmp.iconset" "$tmp.png" "$swift"
    return 0
  fi
  return 1
}

build_app() { # $1=目标名 $2=AppleScript 源码 $3=icns
  local dest="$APP_DIR/$1.app"
  local src="/tmp/psw-applet-$$.applescript"
  printf '%s\n' "$2" > "$src"
  rm -rf "$dest"
  osacompile -o "$dest" "$src" >/dev/null 2>&1
  rm -f "$src"
  if [[ -f "$3" ]]; then
    cp "$3" "$dest/Contents/Resources/applet.icns"
    codesign -f -s - "$dest" >/dev/null 2>&1
  fi
  echo "   ✓ $1.app"
}

menu_script="try
  do shell script \"$DST_DIR/open-menu.sh\"
on error errMsg
  -- open-menu.sh already displayed a dialog
end try"
if gen_icns menu "开关" "0.11" "0.24" "0.85" "0.22" "0.72" "0.98"; then
  build_app "代理切换" "$menu_script" "/tmp/psw-icon-menu.icns"
else
  build_app "代理切换" "$menu_script" ""
fi
rm -f /tmp/psw-icon-menu.icns

echo "==> 3/4 生成桌面启动器"
launch_one() { # $1=显示名 $2=tool $3=icns 名
  local script="try
  do shell script \"$DST_DIR/launch.sh $2\"
on error errMsg
  display dialog errMsg buttons {\"OK\"} default button 1 with title \"proxy-switcher\" with icon stop
end try"
  if [[ -f "/tmp/psw-icon-$3.icns" ]]; then
    build_app "$1" "$script" "/tmp/psw-icon-$3.icns"
  else
    build_app "$1" "$script" ""
  fi
}
if gen_icns oc "OC" "0.04" "0.55" "0.40" "0.20" "0.83" "0.61"; then
  launch_one "OpenCode 代理启动" "opencode" "oc"
else
  launch_one "OpenCode 代理启动" "opencode" ""
fi
if gen_icns ag "AG" "0.44" "0.24" "0.90" "0.65" "0.54" "0.99"; then
  launch_one "Antigravity 代理启动" "antigravity" "ag"
else
  launch_one "Antigravity 代理启动" "antigravity" ""
fi
rm -f /tmp/psw-icon-oc.icns /tmp/psw-icon-ag.icns

echo "==> 4/4 ${1:+挂载 zsh 函数}"
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
echo "  - 菜单：双击 $APP_DIR/代理切换.app（或终端跑 $DST_DIR/switcher.sh）"
echo "  - 桌面端：双击 $APP_DIR/OpenCode 代理启动.app / Antigravity 代理启动.app"
echo "  - CLI：新终端里用 opencode-proxy / agy-proxy"
echo "  - 配置文件：$DST_DIR/config.json"