import AppKit

// 黑底 + Claude 文字配色
private enum Palette {
    static let bg    = NSColor.black                                                 // Touch Bar 原生黑
    static let text  = NSColor(srgbRed: 0.941, green: 0.933, blue: 0.902, alpha: 1)  // 奶油白正文
    static let coral = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)  // #D97757 赤陶橙
    static let red   = NSColor(srgbRed: 0.851, green: 0.357, blue: 0.314, alpha: 1)  // 拒绝
    static let green = NSColor(srgbRed: 0.475, green: 0.690, blue: 0.408, alpha: 1)  // 通过
}

private func emoji(for tool: String) -> String {
    switch tool {
    case "Bash": return "⚡"
    case "Edit", "MultiEdit": return "✏️"
    case "Write": return "📝"
    case "NotebookEdit": return "📓"
    default: return "🔧"
    }
}

private func blend(_ from: NSColor, _ to: NSColor, _ ratio: CGFloat) -> NSColor {
    let a = from.usingColorSpace(.sRGB)!, b = to.usingColorSpace(.sRGB)!
    let t = max(0, min(1, ratio))
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                   alpha: 1)
}

/// Touch Bar 审批视图：黑底 + Claude 文字配色 + 跟手滑块手势。
final class ApprovalView: NSView {
    var onDecision: ((Decision) -> Void)?

    private let summaryField = NSTextField(labelWithString: "")
    private let leftHint = NSTextField(labelWithString: "◀ 拒绝")
    private let rightHint = NSTextField(labelWithString: "通过 ▶")
    private let thumb = CALayer()
    private let thumbArrow = CATextLayer()

    private var startX: CGFloat = 0
    private let threshold: CGFloat = 80
    private let thumbW: CGFloat = 46
    private var tracking = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        allowedTouchTypes = [.direct]
        layer?.backgroundColor = Palette.bg.cgColor

        for f in [summaryField, leftHint, rightHint] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.drawsBackground = false
            f.isBezeled = false
            f.lineBreakMode = .byTruncatingTail
            addSubview(f)
        }
        leftHint.font = .systemFont(ofSize: 12, weight: .medium)
        leftHint.textColor = Palette.red.withAlphaComponent(0.7)
        rightHint.font = .systemFont(ofSize: 12, weight: .medium)
        rightHint.textColor = Palette.green.withAlphaComponent(0.7)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 620),
            leftHint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leftHint.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightHint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rightHint.centerYAnchor.constraint(equalTo: centerYAnchor),
            summaryField.centerXAnchor.constraint(equalTo: centerXAnchor),
            summaryField.centerYAnchor.constraint(equalTo: centerYAnchor),
            summaryField.leadingAnchor.constraint(greaterThanOrEqualTo: leftHint.trailingAnchor, constant: 10),
            summaryField.trailingAnchor.constraint(lessThanOrEqualTo: rightHint.leadingAnchor, constant: -10),
        ])

        // 跟手滑块（盖在文字之上）
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        thumb.backgroundColor = Palette.coral.cgColor
        thumb.cornerRadius = 13
        thumb.zPosition = 100
        thumb.opacity = 0
        thumb.shadowColor = NSColor.black.cgColor
        thumb.shadowOpacity = 0.35
        thumb.shadowRadius = 4
        thumb.shadowOffset = CGSize(width: 0, height: -1)
        thumbArrow.contentsScale = scale
        thumbArrow.alignmentMode = .center
        thumbArrow.foregroundColor = NSColor.white.cgColor
        thumbArrow.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        thumbArrow.fontSize = 17
        thumb.addSublayer(thumbArrow)
        layer?.addSublayer(thumb)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ req: ApprovalRequest) {
        var sum = req.summary.replacingOccurrences(of: "\n", with: " ")
        if sum.count > 42 { sum = String(sum.prefix(42)) + "…" }
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "\(req.session)   ",
            attributes: [.foregroundColor: Palette.text.withAlphaComponent(0.5),
                         .font: NSFont.systemFont(ofSize: 12)]))
        s.append(NSAttributedString(string: "\(emoji(for: req.tool)) ",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        s.append(NSAttributedString(string: "\(req.tool)  ",
            attributes: [.foregroundColor: Palette.coral,
                         .font: NSFont.boldSystemFont(ofSize: 13)]))
        s.append(NSAttributedString(string: sum,
            attributes: [.foregroundColor: Palette.text,
                         .font: NSFont.systemFont(ofSize: 13)]))
        summaryField.attributedStringValue = s
        summaryField.alphaValue = 1
    }

    // MARK: 手势

    override func touchesBegan(with event: NSEvent) {
        guard let p = event.allTouches().first?.location(in: self) else { return }
        startX = p.x
        tracking = true
        summaryField.alphaValue = 0.25       // 滑动时淡化文字，聚焦手势
        CATransaction.begin(); CATransaction.setDisableActions(true)
        thumb.opacity = 1
        place(at: p.x, dx: 0)
        CATransaction.commit()
    }

    override func touchesMoved(with event: NSEvent) {
        guard tracking, let p = event.allTouches().first?.location(in: self) else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        place(at: p.x, dx: p.x - startX)
        CATransaction.commit()
    }

    override func touchesEnded(with event: NSEvent) {
        guard tracking else { return }
        tracking = false
        let endX = event.allTouches().first?.location(in: self).x ?? startX
        let dx = endX - startX
        if dx >= threshold { confirm(.allow) }
        else if dx <= -threshold { confirm(.deny) }
        else { reset() }
    }

    override func touchesCancelled(with event: NSEvent) {
        tracking = false
        reset()
    }

    // MARK: 渲染

    /// 把滑块放到手指位置，并按方向/位移更新颜色、箭头、底色染晕、过阈值放大。
    private func place(at x: CGFloat, dx: CGFloat) {
        let h = bounds.height
        let cx = min(max(x, thumbW / 2), bounds.width - thumbW / 2)
        let th: CGFloat = 26
        thumb.frame = CGRect(x: cx - thumbW / 2, y: (h - th) / 2, width: thumbW, height: th)
        thumbArrow.frame = CGRect(x: 0, y: (th - 20) / 2, width: thumbW, height: 20)

        let mag = min(abs(dx) / threshold, 1)
        if dx > 6 {
            thumbArrow.string = "→"
            thumb.backgroundColor = Palette.green.cgColor
            layer?.backgroundColor = blend(Palette.bg, Palette.green, mag * 0.55).cgColor
        } else if dx < -6 {
            thumbArrow.string = "←"
            thumb.backgroundColor = Palette.red.cgColor
            layer?.backgroundColor = blend(Palette.bg, Palette.red, mag * 0.55).cgColor
        } else {
            thumbArrow.string = "⟷"
            thumb.backgroundColor = Palette.coral.cgColor
            layer?.backgroundColor = Palette.bg.cgColor
        }
        let scale: CGFloat = abs(dx) >= threshold ? 1.18 : 1.0
        thumb.transform = CATransform3DMakeScale(scale, scale, 1)
    }

    /// 松手未过阈值：滑块淡出、底色与文字复原（带隐式动画平滑弹回）。
    private func reset() {
        thumb.opacity = 0
        thumb.transform = CATransform3DIdentity
        layer?.backgroundColor = Palette.bg.cgColor
        summaryField.alphaValue = 1
    }

    /// 确认：底色闪一下对应色，回调决定（随后队列会 dismiss 本视图）。
    private func confirm(_ d: Decision) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let c = (d == .allow ? Palette.green : Palette.red)
        layer?.backgroundColor = c.withAlphaComponent(0.9).cgColor
        thumb.backgroundColor = c.cgColor
        CATransaction.commit()
        onDecision?(d)
    }
}
