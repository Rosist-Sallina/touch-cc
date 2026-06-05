#!/usr/bin/env bash
# touch-cc installer — 双击此文件即可安装
# 零依赖：仅需 macOS 自带工具。无需 Xcode、jq、Homebrew。
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/tbcd.app"
HOOK_DIR="$HOME/.claude/hooks/touchbar-cc"
CODEX_HOOK_DIR="$HOME/.codex/hooks/touchbar-cc"
SETTINGS="$HOME/.claude/settings.json"
CODEX_CONFIG="$HOME/.codex/config.toml"
LA="$HOME/Library/LaunchAgents/com.touchbarcc.tbcd.plist"
CONF_DIR="$HOME/.touchbar-cc"

echo "╔══════════════════════════════════════════╗"
echo "║   touch-cc installer                     ║"
echo "║   Touch Bar × Claude Code / Codex CLI    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# 1. 安装 app
echo "==> 安装 tbcd.app 到 /Applications"
rm -rf "$APP"
cp -R "$DIR/tbcd.app" "$APP"
xattr -cr "$APP" 2>/dev/null || true
echo "    OK"

# 2. 安装 hook 脚本（CC + Codex 共用同一脚本）
echo "==> 安装 hook 脚本"
mkdir -p "$HOOK_DIR"
cp "$DIR/hook.sh" "$HOOK_DIR/hook.sh"
chmod +x "$HOOK_DIR/hook.sh"
mkdir -p "$CODEX_HOOK_DIR"
cp "$DIR/hook.sh" "$CODEX_HOOK_DIR/hook.sh"
chmod +x "$CODEX_HOOK_DIR/hook.sh"
echo "    OK"

# 3. 注入 settings.json（用 python3 代替 jq，macOS 自带）
echo "==> 配置 Claude Code hook (幂等)"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.tbcc-bak" 2>/dev/null || true
/usr/bin/python3 - "$SETTINGS" "$HOOK_DIR/hook.sh" <<'PYEOF'
import sys, json, os
settings_path, hook_cmd_path = sys.argv[1], sys.argv[2]
cmd = f"bash {hook_cmd_path}"
with open(settings_path) as f:
    s = json.load(f)
s.setdefault("hooks", {}).setdefault("PreToolUse", [])
exists = any(cmd in str(e) for e in s["hooks"]["PreToolUse"])
if not exists:
    s["hooks"]["PreToolUse"].append({
        "matcher": ".*",
        "hooks": [{"type": "command", "command": cmd, "timeout": 70}]
    })
with open(settings_path, "w") as f:
    json.dump(s, f, indent=2)
PYEOF
echo "    OK"

# 3b. 配置 Codex CLI hook（若 ~/.codex 存在）
if [ -d "$HOME/.codex" ]; then
echo "==> 配置 Codex CLI hook (幂等)"
[ -f "$CODEX_CONFIG" ] || touch "$CODEX_CONFIG"
cp "$CODEX_CONFIG" "$CODEX_CONFIG.tbcc-bak" 2>/dev/null || true
/usr/bin/python3 - "$CODEX_CONFIG" "$CODEX_HOOK_DIR/hook.sh" <<'PYEOF'
import sys, os

config_path, hook_path = sys.argv[1], sys.argv[2]
cmd = f"bash {hook_path}"

with open(config_path) as f:
    content = f.read()

marker = "# touchbar-cc hook"
if marker in content:
    print("    已存在，跳过")
else:
    block = f"""
{marker}
[[PreToolUse]]
matcher = ".*"
[[PreToolUse.hooks]]
type = "command"
command = "{cmd}"
timeout = 70
"""
    with open(config_path, "a") as f:
        f.write(block)
    print("    已注入")
PYEOF
echo "    OK"
else
echo "==> Codex CLI 未安装，跳过配置"
fi

# 4. 安装 LaunchAgent
echo "==> 安装 LaunchAgent (开机自启)"
mkdir -p "$(dirname "$LA")"
sed "s#__APP_PATH__#$APP#g" "$DIR/LaunchAgent.plist" > "$LA"
launchctl unload "$LA" 2>/dev/null || true
launchctl load "$LA"
echo "    OK"

# 5. 复制卸载脚本到固定位置（用户删了解压目录后仍能找到）
echo "==> 安装卸载脚本"
cp "$DIR/uninstall.command" "$CONF_DIR/uninstall.command"
chmod +x "$CONF_DIR/uninstall.command"
echo "    OK (位于 ~/.touchbar-cc/uninstall.command)"

# 6. 生成默认配置
echo "==> 生成默认配置"
mkdir -p "$CONF_DIR"
if [ ! -f "$CONF_DIR/config.json" ]; then
cat > "$CONF_DIR/config.json" <<'CONFEOF'
{
  "language": "en",
  "threshold": 105,
  "thumbWidth": 54,
  "iconPath": "",
  "uiTimeoutExtra": 5,
  "colors": {
    "background": "#000000",
    "text": "#F0EEE6",
    "coral": "#D97757",
    "red": "#D95B50",
    "green": "#79B068"
  },
  "codexColors": {
    "background": "#000000",
    "text": "#ECECF1",
    "coral": "#10A37F",
    "red": "#EF4444",
    "green": "#10A37F"
  },
  "fonts": { "session": 14, "tool": 16, "summary": 16, "hint": 14 }
}
CONFEOF
echo "    已生成 ~/.touchbar-cc/config.json"
else
echo "    已存在，保留"
fi

echo ""
echo "══════════════════════════════════════════"
echo "  ✓ 安装完成！"
echo ""
echo "  支持 Claude Code + Codex CLI。"
echo "  在 CC / Codex 里执行任意命令即可体验。"
echo ""
echo "  配置: ~/.touchbar-cc/config.json"
echo "  卸载: ~/.touchbar-cc/uninstall.command"
echo "══════════════════════════════════════════"
