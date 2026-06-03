import AppKit

private func emoji(for tool: String) -> String {
    switch tool {
    case "Bash": return "⚡"
    case "Edit", "MultiEdit": return "✏️"
    case "Write": return "📝"
    case "NotebookEdit": return "📓"
    default: return "🔧"
    }
}

/// Touch Bar 上的审批视图：渲染精简摘要，捕获左右滑手势。
final class ApprovalView: NSView {
    var onDecision: ((Decision) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var startX: CGFloat = 0
    private let threshold: CGFloat = 60

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.direct]
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 600)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ req: ApprovalRequest) {
        let sessionTag = req.queueRemaining > 0 ? "[\(req.session) +\(req.queueRemaining)]" : "[\(req.session)]"
        var sum = req.summary.replacingOccurrences(of: "\n", with: " ")
        if sum.count > 35 { sum = String(sum.prefix(35)) + "…" }
        label.stringValue = "✗  \(sessionTag) \(emoji(for: req.tool)) \(req.tool)  \(sum)  ✓"
    }

    override func touchesBegan(with event: NSEvent) {
        startX = event.allTouches().first?.location(in: self).x ?? 0
    }
    override func touchesEnded(with event: NSEvent) {
        let endX = event.allTouches().first?.location(in: self).x ?? 0
        let dx = endX - startX
        if dx > threshold { onDecision?(.allow) }
        else if dx < -threshold { onDecision?(.deny) }
        // 阈值内不触发，等待再次操作
    }
}
