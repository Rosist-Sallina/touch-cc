#!/usr/bin/env bash
# touch-cc uninstaller — 双击此文件即可卸载
set -uo pipefail

LA="$HOME/Library/LaunchAgents/com.touchbarcc.tbcd.plist"
SETTINGS="$HOME/.claude/settings.json"
CODEX_CONFIG="$HOME/.codex/config.toml"

echo "╔══════════════════════════════════════════╗"
echo "║   touch-cc uninstaller                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

echo "==> 停止 tbcd"
launchctl unload "$LA" 2>/dev/null || true
echo "    OK"

echo "==> 移除文件"
rm -f "$LA"
rm -rf /Applications/tbcd.app
rm -rf "$HOME/.claude/hooks/touchbar-cc"
rm -rf "$HOME/.codex/hooks/touchbar-cc"
rm -rf "$HOME/.touchbar-cc"
echo "    OK"

echo "==> 移除 settings.json 中的 hook 条目"
if [ -f "$SETTINGS" ]; then
  /usr/bin/python3 - "$SETTINGS" <<'PYEOF'
import sys, json
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
hooks = s.get("hooks", {}).get("PreToolUse", [])
s["hooks"]["PreToolUse"] = [h for h in hooks if "touchbar-cc" not in str(h)]
with open(path, "w") as f:
    json.dump(s, f, indent=2)
PYEOF
  echo "    OK"
else
  echo "    settings.json 不存在，跳过"
fi

echo "==> 移除 Codex config.toml 中的 hook 条目"
if [ -f "$CODEX_CONFIG" ]; then
  /usr/bin/python3 - "$CODEX_CONFIG" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()
# 删除 # touchbar-cc hook 标记到下一个空行之间的所有行
out, skip = [], False
for line in lines:
    if "# touchbar-cc hook" in line:
        skip = True
        continue
    if skip and line.strip() == "":
        skip = False
        continue
    if skip and (line.startswith("[[") or line.startswith("type") or line.startswith("command") or line.startswith("timeout") or line.startswith("matcher")):
        continue
    skip = False
    out.append(line)
with open(path, "w") as f:
    f.writelines(out)
PYEOF
  echo "    OK"
else
  echo "    config.toml 不存在，跳过"
fi

echo ""
echo "══════════════════════════════════════════"
echo "  ✓ 卸载完成"
echo "══════════════════════════════════════════"
