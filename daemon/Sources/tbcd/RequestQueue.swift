import Foundation

/// 线程安全 FIFO 审批队列。
/// 一次只暴露一条"当前项"给 UI；当前项被 resolve 后自动推进到下一条。
final class RequestQueue {
    private struct Pending { let req: ApprovalRequest; let resolve: (Decision) -> Void }
    private var items: [Pending] = []
    private let lock = NSLock()

    /// 当一个请求成为"当前展示项"时回调。
    var onPresent: ((ApprovalRequest) -> Void)?
    /// 当队列清空时回调（释放 Touch Bar）。
    var onIdle: (() -> Void)?

    /// 当前项之外仍在排队的数量。
    var remaining: Int {
        lock.lock(); defer { lock.unlock() }
        return max(0, items.count - 1)
    }

    func enqueue(_ req: ApprovalRequest, resolve: @escaping (Decision) -> Void) {
        lock.lock()
        items.append(Pending(req: req, resolve: resolve))
        let shouldPresent = items.count == 1
        let current = items.first?.req
        lock.unlock()
        if shouldPresent, let current { onPresent?(current) }
    }

    func resolveCurrent(_ decision: Decision) {
        lock.lock()
        guard !items.isEmpty else { lock.unlock(); return }
        let done = items.removeFirst()
        let next = items.first?.req
        lock.unlock()
        done.resolve(decision)
        if let next { onPresent?(next) } else { onIdle?() }
    }
}
