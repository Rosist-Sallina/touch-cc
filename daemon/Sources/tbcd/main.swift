import AppKit

// 忽略 SIGPIPE：当 hook 客户端已断开、tbcd 仍向其 socket fd write 时（如超时清理），
// 默认 SIGPIPE 会杀死进程；改为让 write 返回 EPIPE 由调用方静默忽略。
signal(SIGPIPE, SIG_IGN)

final class AppDelegate: NSObject, NSApplicationDelegate {
    let queue = RequestQueue()
    let touchBar = TouchBarController()
    var menu: MenuBarController?

    func applicationDidFinishLaunching(_ n: Notification) {
        let capable = TouchBarController.isCapable
        menu = MenuBarController(capable: capable)

        touchBar.onSwipe = { [weak self] decision in
            self?.queue.resolveCurrent(decision)
        }
        queue.onPresent = { [weak self] req in
            NSLog("present: \(req.session) \(req.tool) \(req.summary)")
            DispatchQueue.main.async { self?.touchBar.present(req) }
        }
        queue.onIdle = { [weak self] in
            NSLog("idle: 释放 Touch Bar")
            DispatchQueue.main.async { self?.touchBar.dismiss() }
        }

        let dir = "\(NSHomeDirectory())/.touchbar-cc"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sock = "\(dir)/tbcd.sock"
        do {
            let server = SocketServer(path: sock, queue: queue)
            try server.start()
            NSLog("touchbar-cc 监听 \(sock) capable=\(capable)")
        } catch {
            NSLog("touchbar-cc socket 启动失败: \(error)")
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
