import Foundation

struct ApprovalRequest: Codable {
    let id: String
    let session: String
    let cwd: String
    let tool: String
    let summary: String
    let queueRemaining: Int
    /// hook 端 socket 超时（秒）。tbcd 据此对当前展示项设自动超时，避免 hook 断开后队列卡死。
    /// 带默认值：缺失该键时（旧请求/裸 nc 测试）合成 Decodable 回退到 55。
    var timeout: Int = 55

    enum CodingKeys: String, CodingKey {
        case id, session, cwd, tool, summary, timeout
        case queueRemaining = "queue_remaining"
    }

    static func decode(from line: String) throws -> ApprovalRequest {
        try JSONDecoder().decode(ApprovalRequest.self, from: Data(line.utf8))
    }
}

extension ApprovalRequest {
    // 自定义 decode：timeout 缺失时回退 55。放在 extension 以保留 memberwise init。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        session = try c.decode(String.self, forKey: .session)
        cwd = try c.decode(String.self, forKey: .cwd)
        tool = try c.decode(String.self, forKey: .tool)
        summary = try c.decode(String.self, forKey: .summary)
        queueRemaining = try c.decode(Int.self, forKey: .queueRemaining)
        timeout = try c.decodeIfPresent(Int.self, forKey: .timeout) ?? 55
    }
}

enum Decision: String, Codable { case allow, deny }

struct ApprovalResponse: Codable {
    let id: String
    let decision: Decision

    func encodeLine() -> String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8)! + "\n"
    }
}
