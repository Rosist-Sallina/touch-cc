import XCTest
@testable import tbcd

final class RequestQueueTests: XCTestCase {
    func req(_ id: String) -> ApprovalRequest {
        ApprovalRequest(id: id, session: "p", cwd: "/p", tool: "Bash", summary: "x", queueRemaining: 0)
    }

    func testFIFOOrderAndResolve() {
        let q = RequestQueue()
        var presented: [String] = []
        q.onPresent = { presented.append($0.id) }   // 当某请求成为"当前"时回调

        var got1: Decision?
        q.enqueue(req("a")) { got1 = $0 }            // a 立即成为当前
        var got2: Decision?
        q.enqueue(req("b")) { got2 = $0 }            // b 排队

        XCTAssertEqual(presented, ["a"])             // 只展示 a
        q.resolveCurrent(.allow)                     // a 完成 → 展示 b
        XCTAssertEqual(got1, .allow)
        XCTAssertEqual(presented, ["a", "b"])
        q.resolveCurrent(.deny)
        XCTAssertEqual(got2, .deny)
    }

    func testRemainingCount() {
        let q = RequestQueue()
        q.onPresent = { _ in }
        q.enqueue(req("a")) { _ in }
        q.enqueue(req("b")) { _ in }
        q.enqueue(req("c")) { _ in }
        XCTAssertEqual(q.remaining, 2)               // 当前 a 外还有 b,c
    }
}
