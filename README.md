# touch-cc — Claude Code 权限审批 × Touch Bar

当 Claude Code 发起权限申请时，在 **Touch Bar** 上弹出精简审批条，**右滑通过 / 左滑拒绝**，处理完回到系统默认。一个纯增益的叠加层：不可用 / 超时 / 出错时自动退化为 CC 原生终端提示，绝不卡住你的工作流。

> 仅适用于带 Touch Bar 的 Mac（MacBook Pro 2016–2022）。

## 安装

一行命令（解压后双击 `install.command`）：

```bash
curl -fsSL https://github.com/你的用户名/touch-cc/releases/latest/download/touch-cc.tar.gz | tar xz && ./touch-cc/install.command
```

或手动：下载 `touch-cc.tar.gz`，解压，双击 `install.command`。

**零依赖**：不需要 Xcode、Homebrew、jq。包内是预编译好的 app。

安装后菜单栏出现 **`⌇`** 图标，在 Claude Code 里执行任意命令即可体验 Touch Bar 审批。

## 卸载

双击 `uninstall.command`，或：

```bash
./touch-cc/uninstall.command
```

自动移除 app、LaunchAgent、hook、配置，并清理 `~/.claude/settings.json`。

## 使用

- **右滑** → 通过（Allow）
- **左滑** → 拒绝（Deny）
- **点系统叉叉** → 等同拒绝
- **不操作** → 超时后 CC 回退原生终端提示

支持多个 CC 会话并发：请求排队，一次处理一条，来源项目名显示在 Touch Bar 上。

## 配置

`~/.touchbar-cc/config.json`（安装时自动生成）：

```json
{
  "language": "en",
  "threshold": 105,
  "thumbWidth": 54,
  "iconPath": "",
  "uiTimeoutExtra": 5,
  "colors": {
    "background": "#000000",
    "text": "#F0EEE6",
    "coral": "#D97757",
    "red": "#D95B50",
    "green": "#79B068"
  },
  "fonts": { "session": 14, "tool": 16, "summary": 16, "hint": 14 }
}
```

- `language`: `en` / `zh` / `ja`
- `threshold`: 滑动触发距离（越大越要果断滑）
- `iconPath`: 自定义图标（PNG 路径），空则用内置 Claude 星芒
- `colors`: 全部 hex 可调
- 改完重启 tbcd 生效：`launchctl unload ~/Library/LaunchAgents/com.touchbarcc.tbcd.plist && launchctl load ~/Library/LaunchAgents/com.touchbarcc.tbcd.plist`

## 故障排查

- **菜单栏 `⚠️`**：Touch Bar 私有 API 不可用，所有请求回退终端，不影响正常使用。
- **Touch Bar 没反应**：确认菜单栏有 `⌇`；`log show --predicate 'process == "tbcd"' --last 5m`
- **首次运行被系统拦截**：系统设置 → 隐私与安全性 → 放行。
