# 端到端验证记录 (2026-06-03)

机型 Mac14,7 / macOS 26.5 (Tahoe) / Swift 6.3.2，调试版 tbcd + 手动 hook 调用。

| 场景 | 操作 | 期望 | 结果 |
|------|------|------|------|
| 单条 allow | 右滑 | hook 输出 `permissionDecision:allow` | ✅ 通过 |
| 单条 deny | 左滑 | `permissionDecision:deny` | ✅ 通过（多会话测试中覆盖） |
| 多会话排队 | 并发两条，依次滑 | 一次只显示一条，A 处理完自动切 B | ✅ `present A → present B → idle` |
| 来源区分 | proj-A / proj-B | Touch Bar 显示各自 session 名 | ✅ 通过 |
| 决定分发 | A 左滑 / B 右滑 | A 收 deny、B 收 allow，无串台 | ✅ r1=deny, r2=allow |
| 超时回退 | 不滑，hook 超时 | hook 无输出 → CC 回退原生提示 | ✅ 通过 |
| 队列自动恢复 | 超时后再发一条 | tbcd 当前项自动超时释放，新请求能 present | ✅ `present→idle(8s)→present` |
| 进程存活 | 超时清理 write 断开 fd | tbcd 不被 SIGPIPE 杀死 | ✅ 修复后存活 |
| tbcd 未运行 | socket 连不上 | hook 静默退出，CC 回退 | ✅ hook 单测覆盖 |

## 验证中发现并修复的 bug
1. **队列卡死**：hook 超时断开后 tbcd 当前项永久占用队列、线程泄漏 → 加 `timeout` 字段，当前项设自动超时（hook 超时 +5s）跳过推进。
2. **SIGPIPE 杀进程**：超时清理时 `write` 到已关闭 fd 触发 SIGPIPE 终止 tbcd → 进程级 `signal(SIGPIPE, SIG_IGN)`。

## 已知限制 / 未来增强
- **队列 badge `+N` 未显示**：hook 端发送 `queue_remaining=0`，多条排队时当前项不预告"还有 N 条"。多会话靠 **session 名**区分（已足够区分来源）。如需 `+N`，需 tbcd 在新请求入队时刷新当前项 badge（spec §6 标注的增强）。
- **正式安装后的 CC 实际触发**：本轮用手动 hook 调用验证；`install.sh` 注入全局 settings.json 后由真实 CC 会话触发的端到端，留待安装后由 Master 确认。
