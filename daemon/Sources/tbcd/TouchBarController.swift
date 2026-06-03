import AppKit

// 私有 DFRFoundation 符号（Spike 已验证在 macOS 26.5 可链接可用）。
@_silgen_name("DFRSystemModalShowsCloseBoxWhenFrontMost")
func DFRSystemModalShowsCloseBoxWhenFrontMost(_ show: Bool)

/// 接管 / 释放 Touch Bar，渲染审批界面，把手势结果回调出去。
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let itemId = NSTouchBarItem.Identifier("com.touchbarcc.approval")
    private var touchBar: NSTouchBar?
    private var approvalView: ApprovalView?
    private var pendingReq: ApprovalRequest?
    var onSwipe: ((Decision) -> Void)?

    /// 展示一条审批请求；首次调用接管 Touch Bar，后续仅刷新内容。
    func present(_ req: ApprovalRequest) {
        pendingReq = req
        if touchBar == nil {
            DFRSystemModalShowsCloseBoxWhenFrontMost(false)
            let tb = NSTouchBar()
            tb.delegate = self
            tb.defaultItemIdentifiers = [Self.itemId]
            touchBar = tb
            Self.presentSystemModal(tb)
        } else {
            approvalView?.update(req)
        }
    }

    /// 释放 Touch Bar，回到系统默认。
    func dismiss() {
        if let tb = touchBar { Self.dismissSystemModal(tb) }
        touchBar = nil
        approvalView = nil
        pendingReq = nil
    }

    func touchBar(_ tb: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard id == Self.itemId else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        let v = ApprovalView()
        v.onDecision = { [weak self] d in self?.onSwipe?(d) }
        if let r = pendingReq { v.update(r) }
        approvalView = v
        item.view = v
        return item
    }

    // MARK: 私有 system-modal 调用（与 Spike 一致）
    static func presentSystemModal(_ tb: NSTouchBar) {
        let sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
        guard NSTouchBar.responds(to: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, NSString) -> Void
        unsafeBitCast(NSTouchBar.method(for: sel), to: Fn.self)(
            NSTouchBar.self, sel, tb, "com.touchbarcc.tray" as NSString)
    }
    static func dismissSystemModal(_ tb: NSTouchBar) {
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        guard NSTouchBar.responds(to: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
        unsafeBitCast(NSTouchBar.method(for: sel), to: Fn.self)(NSTouchBar.self, sel, tb)
    }

    /// 启动时的能力探测：私有 selector 是否存在。
    static var isCapable: Bool {
        NSTouchBar.responds(to: NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:"))
    }
}
