#!/usr/bin/env bash
# 纯 bash 测试，无 bats 依赖。验证 hook.sh 的 allow/deny/回退 三条路径。
set -uo pipefail
HOOK="$(dirname "$0")/hook.sh"
SOCK="/tmp/tbcc-test-$$.sock"
PASS=0; FAIL=0
check() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else echo "FAIL: $1 期望[$3] 实际[$2]"; FAIL=$((FAIL+1)); fi; }

# 假 server：监听一次连接，回固定决定后关闭
fake_server() { # $1=decision
  rm -f "$SOCK"
  ( echo "{\"id\":\"x\",\"decision\":\"$1\"}" | nc -lU "$SOCK" >/dev/null 2>&1 ) &
  sleep 0.3
}

INPUT='{"session_id":"s","cwd":"/tmp/proj","tool_name":"Bash","tool_input":{"command":"echo hi"}}'

# 测试1: allow
fake_server allow
OUT=$(echo "$INPUT" | TBCC_SOCK="$SOCK" TBCC_TIMEOUT=5 bash "$HOOK")
echo "$OUT" | grep -q '"permissionDecision":"allow"' && R=ok || R=no
check "allow路径" "$R" "ok"

# 测试2: deny
fake_server deny
OUT=$(echo "$INPUT" | TBCC_SOCK="$SOCK" TBCC_TIMEOUT=5 bash "$HOOK")
echo "$OUT" | grep -q '"permissionDecision":"deny"' && R=ok || R=no
check "deny路径" "$R" "ok"

# 测试3: socket 不存在 → 静默退出，无 permissionDecision
rm -f "$SOCK"
OUT=$(echo "$INPUT" | TBCC_SOCK="$SOCK" TBCC_TIMEOUT=2 bash "$HOOK")
echo "$OUT" | grep -q 'permissionDecision' && R=has || R=none
check "无server回退" "$R" "none"

rm -f "$SOCK"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
