import AppKit
import IOKit.pwr_mgt

// 私有 DFRFoundation 符号（Spike 已验证在 macOS 26.5 可链接可用）。
@_silgen_name("DFRSystemModalShowsCloseBoxWhenFrontMost")
func DFRSystemModalShowsCloseBoxWhenFrontMost(_ show: Bool)

/// 声明一次用户活动，尝试唤醒已变暗/休眠的 Touch Bar（重置系统 idle 计时）。
private func wakeTouchBar() {
    var aid: IOPMAssertionID = 0
    IOPMAssertionDeclareUserActivity("touchbar-cc-approval" as CFString, kIOPMUserActiveLocal, &aid)
}

/// 接管 / 释放 Touch Bar，渲染审批界面，把手势结果回调出去。
final class TouchBarController: NSObject, NSTouchBarDelegate {
    static let itemId = NSTouchBarItem.Identifier("com.touchbarcc.approval")
    private var touchBar: NSTouchBar?
    private var approvalView: ApprovalView?
    private var pendingReq: ApprovalRequest?
    private var timeoutWork: DispatchWorkItem?
    private var selfDismissing = false   // dismiss() 期间为 true，用于区分"自发关闭"与"用户点叉叉"
    var onSwipe: ((Decision) -> Void)?

    /// 展示一条审批请求；首次调用接管 Touch Bar，后续仅刷新内容。
    /// 同时为当前项设自动超时（hook 超时 + 5s 余量），防止 hook 断开后队列卡死。
    func present(_ req: ApprovalRequest) {
        pendingReq = req
        wakeTouchBar()
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
        // 重设当前项的自动超时计时器
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onSwipe?(.deny) }
        timeoutWork = work
        let extra = Double(AppConfig.current.uiTimeoutExtra)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(req.timeout) + extra, execute: work)
    }

    /// 释放 Touch Bar，回到系统默认。
    func dismiss() {
        selfDismissing = true
        timeoutWork?.cancel()
        timeoutWork = nil
        if let tb = touchBar { Self.dismissSystemModal(tb) }
        touchBar = nil
        approvalView = nil
        pendingReq = nil
        selfDismissing = false
    }

    func touchBar(_ tb: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard id == Self.itemId else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        let v = ApprovalView()
        v.onDecision = { [weak self] d in self?.onSwipe?(d) }
        v.onWindowLost = { [weak self] in
            guard let self, !self.selfDismissing, self.touchBar != nil else { return }
            // 用户点了系统叉叉：modal 已被系统关闭，把当前 Touch Bar 状态清空，
            // 当作一次拒绝交给队列推进（下一条请求会重新接管 Touch Bar）。
            self.touchBar = nil
            self.approvalView = nil
            self.pendingReq = nil
            self.timeoutWork?.cancel()
            self.timeoutWork = nil
            NSLog("close-box: 用户点叉叉 → 当前请求按拒绝处理")
            self.onSwipe?(.deny)
        }
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
