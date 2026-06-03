import AppKit

private func blend(_ from: NSColor, _ to: NSColor, _ ratio: CGFloat) -> NSColor {
    let a = from.usingColorSpace(.sRGB)!, b = to.usingColorSpace(.sRGB)!
    let t = max(0, min(1, ratio))
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                   green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                   blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                   alpha: 1)
}

private func loadIcon(_ path: String, size: CGFloat) -> CGImage? {
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path),
          let img = NSImage(contentsOfFile: path) else { return nil }
    var rect = CGRect(x: 0, y: 0, width: size, height: size)
    return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

private func startPulse(_ layer: CALayer) {
    guard layer.animation(forKey: "pulse") == nil else { return }
    let a = CABasicAnimation(keyPath: "transform.scale")
    a.fromValue = 0.82; a.toValue = 1.08; a.duration = 0.6
    a.autoreverses = true; a.repeatCount = .infinity
    a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(a, forKey: "pulse")
}

private final class ClaudeMark: CALayer {
    func build(size: CGFloat, color: CGColor) {
        sublayers?.forEach { $0.removeFromSuperlayer() }
        let n = 11; let pw = size * 0.13; let ph = size * 0.44
        let c = CGPoint(x: size / 2, y: size / 2)
        for i in 0..<n {
            let p = CALayer(); p.backgroundColor = color
            p.cornerRadius = pw / 2
            p.bounds = CGRect(x: 0, y: 0, width: pw, height: ph)
            p.anchorPoint = CGPoint(x: 0.5, y: 0); p.position = c
            p.transform = CATransform3DMakeRotation(CGFloat(i) / CGFloat(n) * .pi * 2, 0, 0, 1)
            addSublayer(p)
        }
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
    }
    func startPulse() { tbcd.startPulse(self) }
}

final class ApprovalView: NSView {
    var onDecision: ((Decision) -> Void)?
    var onWindowLost: (() -> Void)?
    private var wasInWindow = false

    private let cfg = AppConfig.current
    private let leftHint = NSTextField(labelWithString: "")
    private let rightHint = NSTextField(labelWithString: "")
    private let mark = ClaudeMark()
    private let iconLayer = CALayer()
    private var usingCustomIcon = false
    private var activeIcon: CALayer { usingCustomIcon ? iconLayer : mark }
    private let thumb = CALayer()
    private let thumbArrow = CATextLayer()
    private let markSize: CGFloat = 22

    // 滚动：clipLayer 裁剪，scrollLayer 载两份 CATextLayer
    private let clipLayer = CALayer()
    private let scrollLayer = CALayer()
    private let text1 = CATextLayer()
    private let text2 = CATextLayer()
    private let textGap: CGFloat = 80
    private var textWidth: CGFloat = 0
    private var clipWidth: CGFloat = 0

    private var startX: CGFloat = 0
    private var tracking = false
    private var threshold: CGFloat { cfg.threshold }
    private var thumbW: CGFloat { cfg.thumbWidth }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        allowedTouchTypes = [.direct]
        layer?.backgroundColor = cfg.colors.background.cgColor

        for f in [leftHint, rightHint] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.drawsBackground = false; f.isBezeled = false
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
        ])

        // clipLayer: 裁剪区（在 layout 中定位）
        clipLayer.masksToBounds = true
        layer?.addSublayer(clipLayer)
        // scrollLayer: 载两份文字，做平移动画
        clipLayer.addSublayer(scrollLayer)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for t in [text1, text2] {
            t.contentsScale = scale
            t.isWrapped = false
            t.truncationMode = .none
            scrollLayer.addSublayer(t)
        }

        // 图标
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

        // 滑块
        thumb.backgroundColor = cfg.colors.coral.cgColor
        thumb.cornerRadius = 14; thumb.zPosition = 100; thumb.opacity = 0
        thumb.shadowColor = NSColor.black.cgColor
        thumb.shadowOpacity = 0.35; thumb.shadowRadius = 4
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { wasInWindow = true }
        else if wasInWindow { wasInWindow = false; onWindowLost?() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let h = bounds.height
        // clipLayer 在 logo 右侧到 Allow 左侧
        let clipX = leftHint.frame.maxX + markSize + 14
        let clipEnd = rightHint.frame.minX - 10
        clipWidth = max(0, clipEnd - clipX)
        clipLayer.frame = CGRect(x: clipX, y: 0, width: clipWidth, height: h)
        // logo 在 Deny 和 clipLayer 之间
        activeIcon.frame = CGRect(x: leftHint.frame.maxX + 6, y: (h - markSize) / 2,
                                  width: markSize, height: markSize)
        CATransaction.commit()
        setupScroll()
    }

    func update(_ req: ApprovalRequest) {
        let sum = req.summary.replacingOccurrences(of: "\n", with: " ")
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
        text1.string = s
        text2.string = s
        textWidth = ceil(s.size().width)
        activeIcon.opacity = 1
        needsLayout = true
    }

    private func setupScroll() {
        scrollLayer.removeAnimation(forKey: "scroll")
        let h = clipLayer.bounds.height
        let textH: CGFloat = 20
        let y = (h - textH) / 2

        if textWidth <= clipWidth {
            // 短文本居中
            text1.frame = CGRect(x: (clipWidth - textWidth) / 2, y: y, width: textWidth, height: textH)
            text2.isHidden = true
            scrollLayer.frame = CGRect(x: 0, y: 0, width: clipWidth, height: h)
        } else {
            // 长文本：两份首尾相连，招牌式循环
            text2.isHidden = false
            let totalW = textWidth + textGap + textWidth
            text1.frame = CGRect(x: 0, y: y, width: textWidth, height: textH)
            text2.frame = CGRect(x: textWidth + textGap, y: y, width: textWidth, height: textH)
            scrollLayer.frame = CGRect(x: 0, y: 0, width: totalW, height: h)
            let shift = textWidth + textGap
            let duration = Double(shift) / 50.0
            let anim = CABasicAnimation(keyPath: "transform.translation.x")
            anim.fromValue = 0
            anim.toValue = -shift
            anim.duration = duration
            anim.beginTime = CACurrentMediaTime() + 2.0
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .linear)
            scrollLayer.add(anim, forKey: "scroll")
        }
    }

    // MARK: 手势
    override func touchesBegan(with event: NSEvent) {
        guard let p = event.allTouches().first?.location(in: self) else { return }
        startX = p.x; tracking = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        activeIcon.opacity = 0.3; thumb.opacity = 1
        text1.opacity = 0.25; text2.opacity = 0.25
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
        guard tracking else { return }; tracking = false
        let dx = (event.allTouches().first?.location(in: self).x ?? startX) - startX
        if dx >= threshold { confirm(.allow) }
        else if dx <= -threshold { confirm(.deny) }
        else { reset() }
    }
    override func touchesCancelled(with event: NSEvent) { tracking = false; reset() }

    private func place(at x: CGFloat, dx: CGFloat) {
        let h = bounds.height
        let cx = min(max(x, thumbW / 2), bounds.width - thumbW / 2)
        let th: CGFloat = 28
        thumb.frame = CGRect(x: cx - thumbW / 2, y: (h - th) / 2, width: thumbW, height: th)
        thumbArrow.frame = CGRect(x: 0, y: (th - 24) / 2, width: thumbW, height: 24)
        let mag = min(abs(dx) / threshold, 1)
        if dx > 6 {
            thumbArrow.string = "→"; thumb.backgroundColor = cfg.colors.green.cgColor
            layer?.backgroundColor = blend(cfg.colors.background, cfg.colors.green, mag * 0.9).cgColor
        } else if dx < -6 {
            thumbArrow.string = "←"; thumb.backgroundColor = cfg.colors.red.cgColor
            layer?.backgroundColor = blend(cfg.colors.background, cfg.colors.red, mag * 0.9).cgColor
        } else {
            thumbArrow.string = "↔"; thumb.backgroundColor = cfg.colors.coral.cgColor
            layer?.backgroundColor = cfg.colors.background.cgColor
        }
        thumb.transform = CATransform3DMakeScale(abs(dx) >= threshold ? 1.18 : 1.0,
                                                  abs(dx) >= threshold ? 1.18 : 1.0, 1)
    }
    private func reset() {
        thumb.opacity = 0; thumb.transform = CATransform3DIdentity
        layer?.backgroundColor = cfg.colors.background.cgColor
        text1.opacity = 1; text2.opacity = 1; activeIcon.opacity = 1
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
