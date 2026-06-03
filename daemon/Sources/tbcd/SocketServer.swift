import Foundation

/// 监听 Unix domain socket，每个连接读一行 JSON 请求 →投递队列→等决定→写回响应→关闭。
final class SocketServer {
    private let path: String
    private var listenFD: Int32 = -1
    private let queue: RequestQueue

    init(path: String, queue: RequestQueue) {
        self.path = path
        self.queue = queue
    }

    func start() throws {
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EINVAL) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                    strncpy(dst, src, 103)
                }
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) }
        }
        guard bound == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EADDRINUSE) }
        guard listen(listenFD, 16) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EINVAL) }

        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 { continue }
            Thread.detachNewThread { [weak self] in self?.handle(clientFD) }
        }
    }

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        guard let line = readLine(fd), let req = try? ApprovalRequest.decode(from: line) else { return }
        let sem = DispatchSemaphore(value: 0)
        var decision: Decision = .deny
        DispatchQueue.main.async {
            self.queue.enqueue(req) { d in decision = d; sem.signal() }
        }
        sem.wait()
        let resp = ApprovalResponse(id: req.id, decision: decision).encodeLine()
        _ = resp.withCString { write(fd, $0, strlen($0)) }
    }

    private func readLine(_ fd: Int32) -> String? {
        var data = Data(); var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == UInt8(ascii: "\n") { break }
            data.append(byte)
        }
        return data.isEmpty ? nil : String(data: data, encoding: .utf8)
    }
}
