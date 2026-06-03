# touch-cc — Claude Code 权限审批 × Touch Bar

当 Claude Code 发起权限申请时，在 **Touch Bar** 上弹出精简审批条，**右滑通过 / 左滑拒绝**，处理完回到系统默认。一个纯增益的叠加层：不可用 / 超时 / 出错时自动退化为 CC 原生终端提示，绝不卡住你的工作流。

> 仅适用于带 Touch Bar 的 Mac（如 MacBook Pro 13" M2 2022，Apple 最后一代 Touch Bar 机型）。

## 工作原理

```
CC PreToolUse hook (hook.sh) ──unix socket──> tbcd 守护进程 ──私有API──> Touch Bar
        ▲                                          │                      │
        └──────── allow/deny ──────────────────────┘   <──左右滑手势──────┘
```

- **hook.sh**：CC 的 `PreToolUse` hook，把申请发给 tbcd 等决定；任何失败 `exit 0` → CC 回退原生提示。
- **tbcd**：常驻菜单栏的 Swift 守护进程，用私有 `DFRFoundation` API 接管 Touch Bar，FIFO 队列支持多会话并发，每条带自动超时防卡死。
- 详见 `docs/superpowers/specs/` 与 `docs/superpowers/plans/`。

## 要求

- 带 Touch Bar 的 Mac + macOS 13+
- 已安装 Xcode（构建 Swift）。若 `swift build` 报 ManifestAPI 链接错误：
  ```
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```
- `jq`（Homebrew：`brew install jq`）

## 安装

```bash
./install.sh
```

会：构建 release → 组装 `/Applications/tbcd.app` → 安装 hook 到 `~/.claude/hooks/touchbar-cc/` → 幂等注入 `~/.claude/settings.json`（自动备份）→ 装 LaunchAgent 开机自启。

安装后菜单栏出现 **`⌇`**（能用）或 **`⚠️`**（Touch Bar 不可用，请求将回退终端）。在 CC 里跑一条 Bash 命令即可看到 Touch Bar 弹审批条。

## 卸载

```bash
./uninstall.sh
```

移除 app / LaunchAgent / hook 脚本与 `~/.touchbar-cc/`。settings.json 的 hook 条目需手动删除，或恢复 `~/.claude/settings.json.tbcc-bak.*` 备份。

## 故障排查

- **菜单栏是 `⚠️`**：私有 Touch Bar API 在当前系统不可用，所有请求会回退终端 —— 不影响正常使用，只是没有 Touch Bar 审批。
- **Touch Bar 没反应**：确认菜单栏有 `⌇`；查看日志 `log show --predicate 'process == "tbcd"' --last 5m`。
- **首次运行被系统拦截**：到「系统设置 → 隐私与安全性」放行 ad-hoc 签名的 app。
- **CC 没弹 Touch Bar**：确认 `~/.claude/settings.json` 的 `hooks.PreToolUse` 含 touchbar-cc 条目；hook 仅对 `Bash|Edit|Write|MultiEdit|NotebookEdit` 触发。

## 开发

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path daemon      # 逻辑层单测
bash hook/test_hook.sh                # hook 脚本测试
```
