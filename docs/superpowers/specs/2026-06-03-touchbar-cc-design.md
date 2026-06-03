# Touch Bar × Claude Code 权限审批工具 — 设计文档

- **日期**: 2026-06-03
- **作者**: Rosist + 杏目
- **状态**: 设计已确认，待实现
- **目标机型**: MacBook Pro 13" M2 2022 (`Mac14,7`)，macOS 26.5 (Tahoe) —— Apple 最后一代带 Touch Bar 的机器

---

## 1. 概述

当 Claude Code (CC) 发起权限申请时，在 Touch Bar 上临时弹出一个审批界面，显示申请的精简摘要，用户**右滑通过 / 左滑拒绝**，处理完毕后 Touch Bar 恢复系统默认状态。

这是一个**纯增益的叠加层**：当工具不可用、超时或出错时，自动退化为 CC 当前的原生终端权限提示（键盘 y/n），不引入任何新的卡死风险。

### 非目标 (Out of Scope)

- ❌ 常驻仪表盘 / CC 状态展示（明确不做）
- ❌ 危险命令识别与差异化保护（所有申请一视同仁）
- ❌ 跨设备 / 远程审批
- ❌ App Store 上架（使用私有 API，仅供个人使用）

---

## 2. 需求画像（已与用户确认）

| 维度 | 决定 |
|------|------|
| 形态 | 仅在权限申请时弹出接管 Touch Bar，处理完回到系统默认 |
| 显示内容 | 精简摘要：图标 + 工具名 + 关键参数截断 + 会话/项目标识 |
| 交互 | 右滑通过 / 左滑拒绝，所有申请一视同仁，速度优先 |
| 回退策略 | 纯增益叠加层：不可用/超时/出错 → 退化到 CC 原生终端提示 |
| 并发 | 支持多会话并发：请求 FIFO 排队，Touch Bar 标明来源会话 |

---

## 3. 总体架构

```
┌─────────────────────────────────────────────────────┐
│  CC Session A (PreToolUse hook → hook.sh)           │
│  CC Session B (PreToolUse hook → hook.sh)           │
└────────────────┬────────────────────────────────────┘
                 │ Unix domain socket
                 │ ~/.touchbar-cc/tbcd.sock
                 ▼
┌─────────────────────────────────────────────────────┐
│  tbcd  (Touch Bar CC Daemon, Swift)                 │
│  · macOS 菜单栏常驻进程                               │
│  · 请求队列（FIFO，支持多会话并发连接）                │
│  · 接管 Touch Bar / 捕获左右滑手势                    │
│  · 决定后写回对应 socket 连接                         │
└─────────────────────────────────────────────────────┘
                 │ private Touch Bar API
                 ▼
┌─────────────────────────────────────────────────────┐
│  Touch Bar（系统接管模式）                            │
│  [~/proj] ⚡ Bash  npm run build…      ✗      ✓     │
└─────────────────────────────────────────────────────┘
```

### 数据流（单次审批）

1. CC 触发 `PreToolUse` hook，`hook.sh` 把请求 JSON 发到 socket，**阻塞等待响应**
2. `tbcd` 把请求入队；队列空时立即接管 Touch Bar 显示审批界面
3. 用户右滑（通过）或左滑（拒绝），`tbcd` 把决定写回该连接
4. `hook.sh` 收到响应：
   - `allow` → 输出 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}`
   - `deny` → 输出对应 `permissionDecision":"deny"` JSON
   - 超时 / socket 不通 → 静默退出（不输出决定），CC 回退到原生提示
5. Touch Bar 恢复系统默认；队列若有下一条，立即切换显示

---

## 4. 组件拆分

三个独立单元，各自边界清晰、可独立测试。

### ① `hook.sh`（CC hook 脚本，~40 行 shell）

- **职责**: CC 每次权限申请前执行，作为 CC 与 daemon 之间的桥
- **输入**: stdin 的请求 JSON（含 `session_id`、`cwd`、`tool_name`、`tool_input`、`hook_event_name`）
- **逻辑**:
  1. 用 `jq` 提取并构造精简请求负载
  2. 通过 `nc -U` 连接 Unix socket，发送负载，等待单行响应（**60s 超时**）
  3. 根据响应输出对应 `permissionDecision` JSON 到 stdout
  4. 任何失败（连接失败 / 超时 / 非预期响应）→ 静默 `exit 0`，不输出决定字段
- **依赖**: `jq`、`nc`（macOS 自带）
- **注册**: `~/.claude/settings.json` 的 `PreToolUse` matcher，匹配 `Bash|Edit|Write|MultiEdit|NotebookEdit`

### ② `tbcd`（Touch Bar CC Daemon，Swift，~300–500 行）

- **职责**: 接管 Touch Bar、渲染审批界面、捕获手势、管理并发队列
- **结构**:
  - `SocketServer`: 监听 Unix socket，每个连接一个 handler，解析请求 → 投递到队列
  - `RequestQueue`: 线程安全 FIFO；持有当前正在审批的请求；完成后取下一条
  - `TouchBarController`: 接管/释放 Touch Bar，渲染 `ApprovalView`，把手势结果回调给队列
  - `ApprovalView`: 自定义 `NSView`，渲染摘要文本 + ✗/✓，处理 `touchesBegan/Moved/Ended` 检测左右滑（也支持点击 ✗/✓ 作为后备）
  - `MenuBarController`: 菜单栏图标，显示运行状态 / Touch Bar 能力检测结果 / 退出入口
- **Touch Bar 接管**: `NSTouchBar` + 私有 system-modal API（见 §7 Spike），**启动时探测能力**，不可用则进入降级状态（菜单栏显示 ⚠️，所有请求立即回落）

### ③ `install.sh`（一键安装脚本）

- 构建并把 `tbcd.app` 复制到 `/Applications`，加入登录启动项（`LaunchAgent` plist）
- 把 `hook.sh` 写入 `~/.claude/hooks/touchbar-cc/`
- 幂等地把 hook 配置注入 `~/.claude/settings.json`（用 `jq` 合并，保留已有配置）
- 打印验证指引

---

## 5. 通信协议（hook.sh ↔ tbcd）

Unix domain socket，**单行 JSON 请求 → 单行 JSON 响应**。

### 请求（hook.sh → tbcd）

```json
{
  "id": "<uuid>",
  "session": "proj-a",
  "cwd": "/Users/rosist/Projects/proj-a",
  "tool": "Bash",
  "summary": "npm run build -- --watch --mode prod",
  "queue_remaining": 0
}
```

- `session`: 取 `cwd` 末尾目录名，用于 Touch Bar 来源标识
- `summary`: 由 hook.sh 从 `tool_input` 提取的人类可读摘要（Bash→command，Edit/Write→file_path，等）

### 响应（tbcd → hook.sh）

```json
{ "id": "<uuid>", "decision": "allow" }   // 或 "deny"
```

- 超时 / 连接失败时 hook.sh 收不到响应，直接走回退路径

---

## 6. Touch Bar UI

```
┌──────────────────────────────────────────────────────────────────────┐
│  [~/proj]  ⚡ Bash   npm run build -- --watch --mode prod…   ✗   ✓  │
└──────────────────────────────────────────────────────────────────────┘
  会话来源     工具图标 工具名     参数（截断，~35 字符 + …）       拒  过
```

- **左区**: `session` 名，最多 10 字符，灰色小字；队列 >1 时显示剩余数 `[~/proj +2]`
- **中区**: 工具 emoji（`⚡`=Bash, `✏️`=Edit, `📝`=Write/MultiEdit, `📓`=NotebookEdit, 默认 `🔧`）+ 工具名 + 参数截断
- **右区**: `✗`（红，左滑或点击 = 拒绝） | `✓`（绿，右滑或点击 = 通过）
- **手势**: 自定义 view 内水平 pan，位移超过阈值（如 60pt）且方向明确即判定；松手前有视觉跟随反馈

---

## 7. Spike —— 首要验证任务（项目前提）

**整个项目成立的前提是这个 Spike 通过。必须在编写任何业务逻辑之前完成。**

### 目标

写一个最简 Swift 程序（< 50 行），在 macOS 26.5 (Tahoe) 上验证：

1. 用私有 API 接管 Touch Bar（system-modal），显示一段文字
2. 在自定义 view 上捕获到一次左 / 右滑动手势并打印方向
3. 释放 Touch Bar，程序退出

### 候选私有 API（需实测确认在 Tahoe 可用）

- `NSTouchBar` system-modal 呈现：`DFRFoundation.framework` 私有符号，或逆向自 Pock / MTMR 的呈现路径
- 参考实现: [Pock](https://github.com/pigigaldi/Pock)、[MTMR](https://github.com/Toxblh/MTMR) —— 注意二者均较老，Tahoe 兼容性正是本 Spike 要回答的问题

### 决策门

- ✅ **Spike 通过** → 按本设计继续完整实现
- ❌ **Spike 失败**（私有 API 在 Tahoe 失效）→ 回退方案二：借力 BetterTouchTool，交互降级为两个点击按钮 `✗ / ✓`（牺牲左右滑），其余架构（hook.sh + socket + 队列思路）基本复用

---

## 8. 错误处理 & 退化

| 场景 | 行为 |
|------|------|
| `tbcd` 未运行 | `hook.sh` socket 连接立即失败 → 静默退出 → CC 原生提示 |
| `tbcd` 处理中崩溃 | socket 断开 → `hook.sh` 超时退出 → CC 原生提示 |
| 用户 60s 未响应 | `hook.sh` 超时退出 → CC 原生提示 |
| Tahoe 私有 API 不可用 | `tbcd` 启动探测失败 → 菜单栏 ⚠️ → 所有请求立即回落 |
| 多条请求涌入 | FIFO 排队，Touch Bar 一次一条，其余连接阻塞等待各自响应 |
| 同一请求重复 / 乱序 | 用 `id` 关联请求与响应，避免串台 |

---

## 9. 测试策略

- **`hook.sh`（可独立测）**: 用 `socat`/`nc` 起一个假 socket server，喂各种 stdin JSON，断言输出的 `permissionDecision`；专门覆盖超时、连接失败、畸形响应的回退路径
- **`tbcd` 逻辑层**: `RequestQueue`、协议解析做单元测试（不依赖 Touch Bar 硬件）
- **`tbcd` Touch Bar 层**: 手动测试（硬件相关，难自动化）；Spike 即第一轮手测
- **端到端**: 真实 CC 会话触发 Bash 申请，验证滑动 → 放行/拦截；并发开两个会话验证排队
- **回退端到端**: 关闭 `tbcd`，确认 CC 退回原生提示且不卡顿

---

## 10. 待验证的假设（标注不确定性）

> 以下假设需在 Spike / 实现早期用真实 CC 2.x 与 Tahoe 实测确认（本设计基于 hook 机制的通用知识，未经本会话联网核实）：

1. **PreToolUse hook 的 stdin 字段名**（`session_id` / `cwd` / `tool_name` / `tool_input` / `hook_event_name`）—— 以 `claude` 实际输出为准，hook.sh 第一版应先 `cat` dump 一次确认
2. **permissionDecision 契约**: `allow` 跳过提示直接执行 / `deny` 阻止 / 不输出 → 回退原生提示。需确认确切的 JSON 结构与字段名
3. **hook 是否同步阻塞、有无内置超时**: 若 CC 对 hook 有自己的超时上限，需确保 hook.sh 的 60s 不超过它（否则被 CC 强杀）；可能需要把超时调到 CC 上限之内
4. **私有 Touch Bar API 在 macOS 26.5 的可用性** —— 由 Spike 回答

---

## 11. 里程碑

1. **M0 — Spike**: 验证 Touch Bar 接管 + 滑动手势（决策门）
2. **M1 — hook.sh + 协议**: 先 dump 确认 CC 字段；实现脚本 + 假 server 测试
3. **M2 — tbcd 核心**: SocketServer + RequestQueue + 协议（无 UI，单元测试）
4. **M3 — tbcd Touch Bar**: 接入 ApprovalView + 手势 + 队列联动
5. **M4 — 打包安装**: install.sh + LaunchAgent + settings.json 注入
6. **M5 — 端到端 & 回退验证**: 单会话、多会话排队、回退路径
