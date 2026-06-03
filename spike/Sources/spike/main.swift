import AppKit

// 私有 DFRFoundation 符号声明（来自 Pock/MTMR 逆向）
@_silgen_name("DFRSystemModalShowsCloseBoxWhenFrontMost")
func DFRSystemModalShowsCloseBoxWhenFrontMost(_ show: Bool)

// NSTouchBar 私有方法通过 ObjC runtime 调用
extension NSTouchBar {
    static func presentSystemModal(_ touchBar: NSTouchBar, identifier: String) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        if NSTouchBar.responds(to: sel) {
            typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, NSString) -> Void
            let imp = NSTouchBar.method(for: sel)
            let fn = unsafeBitCast(imp, to: Fn.self)
            fn(NSTouchBar.self, sel, touchBar, identifier as NSString)
        } else {
            print("SPIKE-FAIL: presentSystemModalTouchBar selector 不存在")
        }
    }
    static func dismissSystemModal(_ touchBar: NSTouchBar) {
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        guard NSTouchBar.responds(to: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
        let imp = NSTouchBar.method(for: sel)
        unsafeBitCast(imp, to: Fn.self)(NSTouchBar.self, sel, touchBar)
    }
}

final class SwipeView: NSView {
    private var startX: CGFloat = 0
    override func touchesBegan(with event: NSEvent) {
        startX = event.allTouches().first?.location(in: self).x ?? 0
    }
    override func touchesEnded(with event: NSEvent) {
        let endX = event.allTouches().first?.location(in: self).x ?? 0
        let dx = endX - startX
        if abs(dx) > 40 {
            print("SPIKE-OK: 收到滑动 方向=\(dx > 0 ? "右(通过)" : "左(拒绝)") dx=\(Int(dx))")
        } else {
            print("SPIKE: 点击/微动 dx=\(Int(dx))")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    let itemId = NSTouchBarItem.Identifier("com.touchbarcc.spike.item")
    var touchBar: NSTouchBar!

    func applicationDidFinishLaunching(_ n: Notification) {
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [itemId]
        NSTouchBar.presentSystemModal(touchBar, identifier: "com.touchbarcc.spike.tray")
        print("SPIKE: 已尝试接管 Touch Bar，请在 Touch Bar 上左右滑动测试；10 秒后自动退出")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            NSTouchBar.dismissSystemModal(self.touchBar)
            print("SPIKE: 已释放 Touch Bar，退出")
            NSApp.terminate(nil)
        }
    }

    func touchBar(_ tb: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard id == itemId else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        let v = SwipeView()
        v.allowedTouchTypes = [.direct]
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.systemBlue.cgColor
        let label = NSTextField(labelWithString: "← 拒绝   滑我   通过 →")
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            v.widthAnchor.constraint(equalToConstant: 560)
        ])
        item.view = v
        return item
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
