# CC PreToolUse Hook 契约（已确认 2026-06-03）

来源：https://code.claude.com/docs/en/hooks （官方文档）

## 输入（stdin JSON）
- `session_id`、`transcript_path`、`cwd`、`permission_mode`、`hook_event_name`、`effort`
- `tool_name`、`tool_input`（对象，含工具参数）

示例：
```json
{
  "session_id": "abc123",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf /tmp/build" }
}
```

jq 路径：
- 会话标识：`.cwd | split("/") | last`
- 命令：`.tool_input.command`（Bash）
- 文件：`.tool_input.file_path`（Edit/Write/MultiEdit/NotebookEdit）

## 输出（stdout JSON）控制权限
```json
{ "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask|defer",
    "permissionDecisionReason": "..." } }
```
- `allow` 批准 / `deny` 阻止 / `ask` 升级到用户提示 / `defer` 交回正常流程

## 回退保证
- **exit 0 且无 JSON 输出 → 走正常权限流程（CC 原生提示）**。
- 这是本工具"纯增益叠加层"回退的官方依据：任何异常路径 `exit 0` 即可。

## 超时
- `command` 类型默认 **600s**，可在 hook 配置加 `timeout` 覆盖。
- 本工具 hook 内部 socket 超时 55s < 600s，安全；hook 配置可加 `"timeout": 70`。
