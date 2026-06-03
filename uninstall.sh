#!/usr/bin/env bash
set -uo pipefail
LA="$HOME/Library/LaunchAgents/com.touchbarcc.tbcd.plist"
launchctl unload "$LA" 2>/dev/null || true
rm -f "$LA"
rm -rf /Applications/tbcd.app
rm -rf "$HOME/.claude/hooks/touchbar-cc"
echo "已移除 app / LaunchAgent / hook 脚本。"
echo "请手动从 ~/.claude/settings.json 的 hooks.PreToolUse 删除 touchbar-cc 条目"
echo "（或恢复 ~/.claude/settings.json.tbcc-bak.* 备份）。"
rm -rf "$HOME/.touchbar-cc"
