#!/usr/bin/env bash
# touchbar-cc PreToolUse hook
# 把权限申请发到 tbcd 守护进程，等 Touch Bar 决定；任何失败路径 exit 0 → CC 回退原生提示。
# 零外部依赖：仅用 macOS 自带的 bash/printf/nc/uuidgen。
set -uo pipefail

SOCK="${TBCC_SOCK:-$HOME/.touchbar-cc/tbcd.sock}"
TIMEOUT="${TBCC_TIMEOUT:-60}"

INPUT="$(cat)"

# auto mode 下模型已自行判断危险性，直接放行不拦截
perm_mode=$(printf '%s' "$INPUT" | /usr/bin/python3 -c "
import sys,json
try: print(json.load(sys.stdin).get('permission_mode',''))
except: pass
" 2>/dev/null) || true
if [ "$perm_mode" = "auto" ]; then
  exit 0
fi

# 轻量 JSON 提取（纯 bash，不依赖 jq）
json_str() {
  printf '%s' "$INPUT" | /usr/bin/python3 -c "
import sys,json
try:
  d=json.load(sys.stdin); $1
except: sys.exit(1)
" 2>/dev/null
}

session=$(json_str "print(d.get('cwd','').rsplit('/',1)[-1])") || exit 0
cwd=$(json_str "print(d.get('cwd',''))") || exit 0
tool=$(json_str "print(d.get('tool_name','?'))") || exit 0

case "$tool" in
  Bash) summary=$(json_str "print(d.get('tool_input',{}).get('command',''))") ;;
  Edit|Write|MultiEdit|NotebookEdit) summary=$(json_str "print(d.get('tool_input',{}).get('file_path',''))") ;;
  *) summary=$(json_str "import json as j;print(j.dumps(d.get('tool_input',{})))") ;;
esac

id=$(/usr/bin/uuidgen)

# 手工构造 JSON（避免依赖 jq）
esc() { printf '%s' "$1" | /usr/bin/python3 -c "import sys,json;print(json.dumps(sys.stdin.read()),end='')"; }
req="{\"id\":$(esc "$id"),\"session\":$(esc "$session"),\"cwd\":$(esc "$cwd"),\"tool\":$(esc "$tool"),\"summary\":$(esc "$summary"),\"queue_remaining\":0,\"timeout\":$TIMEOUT}"

# 连 socket，发请求，读一行响应（超时回退）
resp=$(printf '%s\n' "$req" | nc -U -w "$TIMEOUT" "$SOCK" 2>/dev/null | head -1) || exit 0
[ -z "$resp" ] && exit 0

# 提取 decision 字段
decision=$(printf '%s' "$resp" | /usr/bin/python3 -c "
import sys,json
try: print(json.load(sys.stdin).get('decision',''))
except: pass
" 2>/dev/null) || exit 0

case "$decision" in
  allow) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"touchbar approved"}}\n' ;;
  deny)  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"touchbar rejected"}}\n' ;;
  *) exit 0 ;;
esac
exit 0
