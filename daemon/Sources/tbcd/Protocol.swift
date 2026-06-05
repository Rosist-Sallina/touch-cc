import Foundation

enum ClientKind: String, Codable { case cc, codex }

struct ApprovalRequest: Codable {
    let id: String
    let session: String
    let cwd: String
    let tool: String
    let summary: String
    let queueRemaining: Int
    var client: ClientKind = .cc
    var timeout: Int = 55

    enum CodingKeys: String, CodingKey {
        case id, session, cwd, tool, summary, timeout, client
        case queueRemaining = "queue_remaining"
    }

    static func decode(from line: String) throws -> ApprovalRequest {
        try JSONDecoder().decode(ApprovalRequest.self, from: Data(line.utf8))
    }
}

extension ApprovalRequest {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        session = try c.decode(String.self, forKey: .session)
        cwd = try c.decode(String.self, forKey: .cwd)
        tool = try c.decode(String.self, forKey: .tool)
        summary = try c.decode(String.self, forKey: .summary)
        queueRemaining = try c.decode(Int.self, forKey: .queueRemaining)
        client = try c.decodeIfPresent(ClientKind.self, forKey: .client) ?? .cc
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
