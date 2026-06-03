import AppKit

private func blend(_ from: NSColor, _ to: NSColor, _ ratio: CGFloat) -> NSColor {
    let a = from.usingColorSpace(.sRGB)!, b = to.usingColorSpace(.sRGB)!
    let t = max(0, min(1, ratio))
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                   alpha: 1)
}

/// 从路径加载图标图片（PNG/JPG/PDF/SVG via NSImage）。空路径或加载失败返回 nil → 回退星芒。
private func loadIcon(_ path: String, size: CGFloat) -> CGImage? {
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path),
          let img = NSImage(contentsOfFile: path) else { return nil }
    var rect = CGRect(x: 0, y: 0, width: size, height: size)
    return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

/// 给任意 layer 加无限脉动跳动动画。
private func startPulse(_ layer: CALayer) {
    guard layer.animation(forKey: "pulse") == nil else { return }
    let a = CABasicAnimation(keyPath: "transform.scale")
    a.fromValue = 0.82
    a.toValue = 1.08
    a.duration = 0.6
    a.autoreverses = true
    a.repeatCount = .infinity
    a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(a, forKey: "pulse")
}

/// Claude 风格放射星芒：N 片圆角花瓣绕中心放射，可脉动跳动。
private final class ClaudeMark: CALayer {
    func build(size: CGFloat, color: CGColor) {
        sublayers?.forEach { $0.removeFromSuperlayer() }
        let n = 11
        let petalW = size * 0.13
        let petalH = size * 0.44
        let center = CGPoint(x: size / 2, y: size / 2)
        for i in 0..<n {
            let petal = CALayer()
            petal.backgroundColor = color
            petal.cornerRadius = petalW / 2
            petal.bounds = CGRect(x: 0, y: 0, width: petalW, height: petalH)
            petal.anchorPoint = CGPoint(x: 0.5, y: 0)   // 绕底端旋转 → 从中心向外放射
            petal.position = center
            petal.transform = CATransform3DMakeRotation(CGFloat(i) / CGFloat(n) * .pi * 2, 0, 0, 1)
            addSublayer(petal)
        }
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
    }

    func startPulse() {
        guard animation(forKey: "pulse") == nil else { return }
        let a = CABasicAnimation(keyPath: "transform.scale")
        a.fromValue = 0.82
        a.toValue = 1.08
        a.duration = 0.6
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        add(a, forKey: "pulse")
    }
}

/// Touch Bar 审批视图：黑底 + Claude 配色 + 星芒图标 + 跟手滑块手势。配色/字号/语言来自 AppConfig。
final class ApprovalView: NSView {
    var onDecision: ((Decision) -> Void)?
    /// 视图被移出窗口时回调（用于侦测用户点击系统叉叉关闭 modal）。
    var onWindowLost: (() -> Void)?
    private var wasInWindow = false

    private let cfg = AppConfig.current
    private let summaryField = NSTextField(labelWithString: "")
    private let leftHint = NSTextField(labelWithString: "")
    private let rightHint = NSTextField(labelWithString: "")
    private let mark = ClaudeMark()
    private let iconLayer = CALayer()
    private var usingCustomIcon = false
    private var activeIcon: CALayer { usingCustomIcon ? iconLayer : mark }
    private let thumb = CALayer()
    private let thumbArrow = CATextLayer()
    private let markSize: CGFloat = 22

    private var startX: CGFloat = 0
    private var tracking = false
    private var threshold: CGFloat { cfg.threshold }
    private var thumbW: CGFloat { cfg.thumbWidth }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        allowedTouchTypes = [.direct]
        layer?.backgroundColor = cfg.colors.background.cgColor

        for f in [summaryField, leftHint, rightHint] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.drawsBackground = false
            f.isBezeled = false
            f.lineBreakMode = .byTruncatingTail
            addSubview(f)
        }
        leftHint.stringValue = "◀ \(L10n.deny(cfg.language))"
        leftHint.font = .systemFont(ofSize: cfg.fonts.hint, weight: .semibold)
        leftHint.textColor = cfg.colors.red.withAlphaComponent(0.85)
        rightHint.stringValue = "\(L10n.allow(cfg.language)) ▶"
        rightHint.font = .systemFont(ofSize: cfg.fonts.hint, weight: .semibold)
        rightHint.textColor = cfg.colors.green.withAlphaComponent(0.85)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 620),
            leftHint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leftHint.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightHint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rightHint.centerYAnchor.constraint(equalTo: centerYAnchor),
            summaryField.centerXAnchor.constraint(equalTo: centerXAnchor, constant: markSize / 2 + 4),
            summaryField.centerYAnchor.constraint(equalTo: centerYAnchor),
            summaryField.leadingAnchor.constraint(greaterThanOrEqualTo: leftHint.trailingAnchor, constant: 36),
            summaryField.trailingAnchor.constraint(lessThanOrEqualTo: rightHint.leadingAnchor, constant: -10),
        ])

        // 图标（文字左侧，layout() 中定位）：优先自定义图片，否则内置 Claude 星芒
        if let img = loadIcon(cfg.iconPath, size: markSize) {
            usingCustomIcon = true
            iconLayer.contents = img
            iconLayer.contentsGravity = .resizeAspect
            iconLayer.frame = CGRect(x: 0, y: 0, width: markSize, height: markSize)
            startPulse(iconLayer)
            layer?.addSublayer(iconLayer)
        } else {
            mark.build(size: markSize, color: cfg.colors.coral.cgColor)
            mark.startPulse()
            layer?.addSublayer(mark)
        }

        // 跟手滑块（盖在最上层）
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        thumb.backgroundColor = cfg.colors.coral.cgColor
        thumb.cornerRadius = 14
        thumb.zPosition = 100
        thumb.opacity = 0
        thumb.shadowColor = NSColor.black.cgColor
        thumb.shadowOpacity = 0.35
        thumb.shadowRadius = 4
        thumb.shadowOffset = CGSize(width: 0, height: -1)
        thumbArrow.contentsScale = scale
        thumbArrow.alignmentMode = .center
        thumbArrow.foregroundColor = NSColor.white.cgColor
        thumbArrow.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        thumbArrow.fontSize = 20
        thumb.addSublayer(thumbArrow)
        layer?.addSublayer(thumb)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 侦测视图被移出窗口：曾在窗口里、现在 window==nil → 系统层关闭了 modal（用户点叉叉）。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            wasInWindow = true
        } else if wasInWindow {
            wasInWindow = false
            onWindowLost?()
        }
    }

    override func layout() {
        super.layout()
        // 把图标放在 summary 文字左侧
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let fx = summaryField.frame.minX
        activeIcon.frame = CGRect(x: fx - 7 - markSize, y: (bounds.height - markSize) / 2,
                                  width: markSize, height: markSize)
        CATransaction.commit()
    }

    func update(_ req: ApprovalRequest) {
        var sum = req.summary.replacingOccurrences(of: "\n", with: " ")
        if sum.count > 42 { sum = String(sum.prefix(42)) + "…" }
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "\(req.session)   ",
            attributes: [.foregroundColor: cfg.colors.text.withAlphaComponent(0.5),
                         .font: NSFont.systemFont(ofSize: cfg.fonts.session)]))
        s.append(NSAttributedString(string: "\(req.tool)  ",
            attributes: [.foregroundColor: cfg.colors.coral,
                         .font: NSFont.boldSystemFont(ofSize: cfg.fonts.tool)]))
        s.append(NSAttributedString(string: sum,
            attributes: [.foregroundColor: cfg.colors.text,
                         .font: NSFont.systemFont(ofSize: cfg.fonts.summary)]))
        summaryField.attributedStringValue = s
        summaryField.alphaValue = 1
        activeIcon.opacity = 1
        needsLayout = true
    }

    // MARK: 手势

    override func touchesBegan(with event: NSEvent) {
        guard let p = event.allTouches().first?.location(in: self) else { return }
        startX = p.x
        tracking = true
        summaryField.alphaValue = 0.25
        CATransaction.begin(); CATransaction.setDisableActions(true)
        activeIcon.opacity = 0.3
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

    private func place(at x: CGFloat, dx: CGFloat) {
        let h = bounds.height
        let cx = min(max(x, thumbW / 2), bounds.width - thumbW / 2)
        let th: CGFloat = 28
        thumb.frame = CGRect(x: cx - thumbW / 2, y: (h - th) / 2, width: thumbW, height: th)
        thumbArrow.frame = CGRect(x: 0, y: (th - 24) / 2, width: thumbW, height: 24)

        let mag = min(abs(dx) / threshold, 1)
        if dx > 6 {
            thumbArrow.string = "→"
            thumb.backgroundColor = cfg.colors.green.cgColor
            layer?.backgroundColor = blend(cfg.colors.background, cfg.colors.green, mag * 0.9).cgColor
        } else if dx < -6 {
            thumbArrow.string = "←"
            thumb.backgroundColor = cfg.colors.red.cgColor
            layer?.backgroundColor = blend(cfg.colors.background, cfg.colors.red, mag * 0.9).cgColor
        } else {
            thumbArrow.string = "↔"
            thumb.backgroundColor = cfg.colors.coral.cgColor
            layer?.backgroundColor = cfg.colors.background.cgColor
        }
        thumb.transform = CATransform3DMakeScale(abs(dx) >= threshold ? 1.18 : 1.0,
                                                  abs(dx) >= threshold ? 1.18 : 1.0, 1)
    }

    private func reset() {
        thumb.opacity = 0
        thumb.transform = CATransform3DIdentity
        layer?.backgroundColor = cfg.colors.background.cgColor
        summaryField.alphaValue = 1
        activeIcon.opacity = 1
    }

    private func confirm(_ d: Decision) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let c = (d == .allow ? cfg.colors.green : cfg.colors.red)
        layer?.backgroundColor = c.withAlphaComponent(0.9).cgColor
        thumb.backgroundColor = c.cgColor
        CATransaction.commit()
        onDecision?(d)
    }
}
