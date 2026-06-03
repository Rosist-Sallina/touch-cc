#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/tbcd.app"
HOOK_DIR="$HOME/.claude/hooks/touchbar-cc"
SETTINGS="$HOME/.claude/settings.json"
LA="$HOME/Library/LaunchAgents/com.touchbarcc.tbcd.plist"

# 让 swift 用 Xcode 工具链（若 xcode-select 未指向 Xcode）
if [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "==> 构建 release"
( cd "$ROOT/daemon" && swift build -c release )

echo "==> 组装 .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/daemon/.build/release/tbcd" "$APP/Contents/MacOS/tbcd"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "(ad-hoc 签名跳过)"

echo "==> 安装 hook"
mkdir -p "$HOOK_DIR"
cp "$ROOT/hook/hook.sh" "$HOOK_DIR/hook.sh"
chmod +x "$HOOK_DIR/hook.sh"

echo "==> 注入 settings.json (幂等)"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.tbcc-bak.$(date +%s)" 2>/dev/null || true
TMP="$(mktemp)"
jq --arg cmd "bash $HOOK_DIR/hook.sh" '
  .hooks //= {} |
  .hooks.PreToolUse //= [] |
  if any(.hooks.PreToolUse[]?; (.hooks // [])[]?.command == $cmd) then .
  else .hooks.PreToolUse += [{
    "matcher":"Bash|Edit|Write|MultiEdit|NotebookEdit",
    "hooks":[{"type":"command","command":$cmd,"timeout":70}]
  }] end
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"

echo "==> 安装 LaunchAgent"
mkdir -p "$(dirname "$LA")"
sed "s#__APP_PATH__#$APP#g" "$ROOT/packaging/com.touchbarcc.tbcd.plist" > "$LA"
launchctl unload "$LA" 2>/dev/null || true
launchctl load "$LA"

echo "==> 完成。tbcd 已启动并随登录运行。"
echo "    验证: 菜单栏应出现 ⌇ 图标；在 CC 里跑一条 Bash 命令试试。"
echo "    若图标为 ⚠️，表示 Touch Bar 私有 API 不可用，请求会回退终端。"
