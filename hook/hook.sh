#!/usr/bin/env bash
# touchbar-cc PreToolUse hook
# 把权限申请发到 tbcd 守护进程，等 Touch Bar 决定；任何失败路径 exit 0 → CC 回退原生提示。
set -uo pipefail

SOCK="${TBCC_SOCK:-$HOME/.touchbar-cc/tbcd.sock}"
TIMEOUT="${TBCC_TIMEOUT:-55}"

INPUT="$(cat)"

# 提取字段（任何 jq 错误都静默放行）
session=$(printf '%s' "$INPUT" | jq -r '.cwd // "" | split("/") | last' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || exit 0
tool=$(printf '%s' "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null) || exit 0

# 摘要：按工具类型取关键参数
case "$tool" in
  Bash) summary=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) ;;
  Edit|Write|MultiEdit|NotebookEdit) summary=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) ;;
  *) summary=$(printf '%s' "$INPUT" | jq -rc '.tool_input // {}' 2>/dev/null) ;;
esac

id=$(/usr/bin/uuidgen)
req=$(jq -nc --arg id "$id" --arg s "$session" --arg c "$cwd" --arg t "$tool" --arg sum "$summary" \
  '{id:$id,session:$s,cwd:$c,tool:$t,summary:$sum,queue_remaining:0}')

# 连 socket，发请求，读一行响应（超时回退）
resp=$(printf '%s\n' "$req" | nc -U -w "$TIMEOUT" "$SOCK" 2>/dev/null | head -1) || exit 0
[ -z "$resp" ] && exit 0

decision=$(printf '%s' "$resp" | jq -r '.decision // ""' 2>/dev/null) || exit 0

case "$decision" in
  allow) jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:"touchbar approved"}}' ;;
  deny)  jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"touchbar rejected"}}' ;;
  *) exit 0 ;;  # 未知响应 → 回退
esac
exit 0
