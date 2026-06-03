import AppKit

/// 菜单栏图标：显示运行状态 / Touch Bar 能力 / 退出入口。
final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(capable: Bool) {
        statusItem.button?.title = capable ? "⌇" : "⚠️"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: capable ? "touchbar-cc 运行中" : "Touch Bar 不可用（请求将回退终端）",
            action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
