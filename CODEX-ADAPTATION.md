# Codex CLI 适配 — 已完成

## 改动清单

### 1. `hook/hook.sh`
- auto mode 检测兼容 Codex 的 `dontAsk` / `bypassPermissions`
- 自动检测调用方（Codex 输入有 `turn_id` 字段，CC 没有），传 `client` 字段给 daemon

### 2. `daemon/Sources/tbcd/Protocol.swift`
- 新增 `ClientKind` 枚举（`.cc` / `.codex`）
- `ApprovalRequest` 加 `client` 字段，默认 `.cc`（兼容旧请求）

### 3. `daemon/Sources/tbcd/Config.swift`
- 新增 `codexColors` 配色方案（OpenAI 品牌色：绿 `#10A37F`，文字 `#ECECF1`，红 `#EF4444`）
- `colors(for:)` 方法根据 client 返回对应配色
- config.json 支持 `codexColors` 自定义

### 4. `daemon/Sources/tbcd/ApprovalView.swift`
- 新增 `OpenAIMark` 类：六瓣花朵+内六边形 logo（CAShapeLayer 绘制）
- 两个 logo（ClaudeMark / OpenAIMark）均预建，`update()` 时按 client 切换可见性
- 所有颜色引用改为 `activeColors` 动态获取
- hint 文字颜色、背景色、滑块颜色均随 client 动态切换

### 5. `dist-assets/install.command`
- Hook 脚本同时安装到 `~/.claude/hooks/` 和 `~/.codex/hooks/`
- 检测 `~/.codex/` 存在时，注入 `[[PreToolUse]]` 到 `~/.codex/config.toml`
- 默认 config.json 包含 `codexColors`

### 6. `dist-assets/uninstall.command`
- 清理 `~/.codex/hooks/touchbar-cc/`
- 清理 `~/.codex/config.toml` 中注入的 hook 条目

## 不需要改的
- daemon 的 socket 协议、队列、TouchBarController — 完全不变
- build-release.sh — 不变

## Codex vs CC Hook 协议对比

| 项目 | Claude Code | Codex CLI |
|------|------------|-----------|
| 输入字段 | `session_id, cwd, tool_name, tool_input, permission_mode` | 同左 + `turn_id, model, tool_use_id` |
| 输出格式 | `hookSpecificOutput.permissionDecision: allow/deny/ask` | 完全相同 |
| 自动模式 | `permission_mode: "auto"` | `"dontAsk"` / `"bypassPermissions"` |
| 配置文件 | `~/.claude/settings.json` (JSON) | `~/.codex/config.toml` (TOML) |

## 品牌配色

| 元素 | Claude | Codex |
|------|--------|-------|
| 主色(coral) | `#D97757` 珊瑚橘 | `#10A37F` OpenAI 绿 |
| 文字 | `#F0EEE6` 暖白 | `#ECECF1` 冷白 |
| 拒绝 | `#D95B50` 红 | `#EF4444` 红 |
| 通过 | `#79B068` 绿 | `#10A37F` 绿 |
| Logo | 11瓣星芒(ClaudeMark) | 六瓣花朵(OpenAIMark) |
