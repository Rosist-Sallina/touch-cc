import XCTest
@testable import tbcd

final class ProtocolTests: XCTestCase {
    func testDecodeRequest() throws {
        let json = #"{"id":"abc","session":"proj","cwd":"/x/proj","tool":"Bash","summary":"echo hi","queue_remaining":2}"#
        let req = try ApprovalRequest.decode(from: json)
        XCTAssertEqual(req.id, "abc")
        XCTAssertEqual(req.tool, "Bash")
        XCTAssertEqual(req.summary, "echo hi")
        XCTAssertEqual(req.queueRemaining, 2)
    }

    func testEncodeResponse() throws {
        let line = ApprovalResponse(id: "abc", decision: .allow).encodeLine()
        XCTAssertTrue(line.contains("\"id\":\"abc\""))
        XCTAssertTrue(line.contains("\"decision\":\"allow\""))
        XCTAssertTrue(line.hasSuffix("\n"))
    }
}
