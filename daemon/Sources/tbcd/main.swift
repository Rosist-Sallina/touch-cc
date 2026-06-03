// 临时入口（M2 Task 6）：验证 socket 链路，收到请求即自动 allow。
// M3 Task 9 覆盖为正式守护进程（接 Touch Bar）。
import Foundation

let q = RequestQueue()
q.onPresent = { req in
    FileHandle.standardError.write("收到请求: \(req.session) \(req.tool) \(req.summary)\n".data(using: .utf8)!)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { q.resolveCurrent(.allow) }
}

let dir = "\(NSHomeDirectory())/.touchbar-cc"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let sock = "\(dir)/tbcd.sock"
let server = SocketServer(path: sock, queue: q)
do {
    try server.start()
    FileHandle.standardError.write("监听: \(sock)\n".data(using: .utf8)!)
} catch {
    FileHandle.standardError.write("socket 启动失败: \(error)\n".data(using: .utf8)!)
    exit(1)
}
RunLoop.main.run()
