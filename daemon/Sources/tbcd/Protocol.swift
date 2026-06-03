import Foundation

struct ApprovalRequest: Codable {
    let id: String
    let session: String
    let cwd: String
    let tool: String
    let summary: String
    let queueRemaining: Int

    enum CodingKeys: String, CodingKey {
        case id, session, cwd, tool, summary
        case queueRemaining = "queue_remaining"
    }

    static func decode(from line: String) throws -> ApprovalRequest {
        try JSONDecoder().decode(ApprovalRequest.self, from: Data(line.utf8))
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
