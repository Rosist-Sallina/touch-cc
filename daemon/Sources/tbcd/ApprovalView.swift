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

private final class OpenAIMark: CALayer {
    private static let svgTemplate = """
    <svg fill="__COLOR__" fill-rule="evenodd" height="__SIZE__" viewBox="0 0 24 24" width="__SIZE__" xmlns="http://www.w3.org/2000/svg"><path d="M9.205 8.658v-2.26c0-.19.072-.333.238-.428l4.543-2.616c.619-.357 1.356-.523 2.117-.523 2.854 0 4.662 2.212 4.662 4.566 0 .167 0 .357-.024.547l-4.71-2.759a.797.797 0 00-.856 0l-5.97 3.473zm10.609 8.8V12.06c0-.333-.143-.57-.429-.737l-5.97-3.473 1.95-1.118a.433.433 0 01.476 0l4.543 2.617c1.309.76 2.189 2.378 2.189 3.948 0 1.808-1.07 3.473-2.76 4.163zM7.802 12.703l-1.95-1.142c-.167-.095-.239-.238-.239-.428V5.899c0-2.545 1.95-4.472 4.591-4.472 1 0 1.927.333 2.712.928L8.23 5.067c-.285.166-.428.404-.428.737v6.898zM12 15.128l-2.795-1.57v-3.33L12 8.658l2.795 1.57v3.33L12 15.128zm1.796 7.23c-1 0-1.927-.332-2.712-.927l4.686-2.712c.285-.166.428-.404.428-.737v-6.898l1.974 1.142c.167.095.238.238.238.428v5.233c0 2.545-1.974 4.472-4.614 4.472zm-5.637-5.303l-4.544-2.617c-1.308-.761-2.188-2.378-2.188-3.948A4.482 4.482 0 014.21 6.327v5.423c0 .333.143.571.428.738l5.947 3.449-1.95 1.118a.432.432 0 01-.476 0zm-.262 3.9c-2.688 0-4.662-2.021-4.662-4.519 0-.19.024-.38.047-.57l4.686 2.71c.286.167.571.167.856 0l5.97-3.448v2.26c0 .19-.07.333-.237.428l-4.543 2.616c-.619.357-1.356.523-2.117.523zm5.899 2.83a5.947 5.947 0 005.827-4.756C22.287 18.339 24 15.84 24 13.296c0-1.665-.713-3.282-1.998-4.448.119-.5.19-.999.19-1.498 0-3.401-2.759-5.947-5.946-5.947-.642 0-1.26.095-1.88.31A5.962 5.962 0 0010.205 0a5.947 5.947 0 00-5.827 4.757C1.713 5.447 0 7.945 0 10.49c0 1.666.713 3.283 1.998 4.448-.119.5-.19 1-.19 1.499 0 3.401 2.759 5.946 5.946 5.946.642 0 1.26-.095 1.88-.309a5.96 5.96 0 004.162 1.713z"></path></svg>
    """

    func build(size: CGFloat, color: CGColor) {
        sublayers?.forEach { $0.removeFromSuperlayer() }
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        let nc = NSColor(cgColor: color) ?? .white
        let rc = nc.usingColorSpace(.sRGB) ?? nc
        let hex = String(format: "#%02X%02X%02X",
                         Int(rc.redComponent * 255),
                         Int(rc.greenComponent * 255),
                         Int(rc.blueComponent * 255))
        let px = Int(size * (NSScreen.main?.backingScaleFactor ?? 2))
        let svg = Self.svgTemplate
            .replacingOccurrences(of: "__COLOR__", with: hex)
            .replacingOccurrences(of: "__SIZE__", with: "\(px)")
        guard let data = svg.data(using: .utf8),
              let image = NSImage(data: data) else { return }
        var rect = CGRect(x: 0, y: 0, width: size, height: size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        contents = cg
        contentsGravity = .resizeAspect
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
    private let claudeMark = ClaudeMark()
    private let openaiMark = OpenAIMark()
    private let iconLayer = CALayer()
    private var usingCustomIcon = false
    private var currentClient: ClientKind = .cc
    private var activeIcon: CALayer {
        if usingCustomIcon { return iconLayer }
        return currentClient == .codex ? openaiMark : claudeMark
    }
    private var activeColors: AppConfig.Colors { cfg.colors(for: currentClient) }
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

        // 图标：三种都预建，update 时按 client 切换可见性
        if let img = loadIcon(cfg.iconPath, size: markSize) {
            usingCustomIcon = true
            iconLayer.contents = img
            iconLayer.contentsGravity = .resizeAspect
            iconLayer.frame = CGRect(x: 0, y: 0, width: markSize, height: markSize)
            startPulse(iconLayer)
            layer?.addSublayer(iconLayer)
        } else {
            claudeMark.build(size: markSize, color: cfg.colors.coral.cgColor)
            claudeMark.startPulse()
            layer?.addSublayer(claudeMark)

            openaiMark.build(size: markSize, color: cfg.codexColors.coral.cgColor)
            openaiMark.startPulse()
            openaiMark.opacity = 0
            layer?.addSublayer(openaiMark)
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
        currentClient = req.client
        let colors = activeColors

        // 切换 logo 可见性
        if !usingCustomIcon {
            claudeMark.opacity = currentClient == .cc ? 1 : 0
            openaiMark.opacity = currentClient == .codex ? 1 : 0
        }

        // 切换 hint 颜色
        leftHint.textColor = colors.red.withAlphaComponent(0.85)
        rightHint.textColor = colors.green.withAlphaComponent(0.85)
        layer?.backgroundColor = colors.background.cgColor
        thumb.backgroundColor = colors.coral.cgColor

        let sum = req.summary.replacingOccurrences(of: "\n", with: " ")
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "\(req.session)   ",
            attributes: [.foregroundColor: colors.text.withAlphaComponent(0.5),
                         .font: NSFont.systemFont(ofSize: cfg.fonts.session)]))
        s.append(NSAttributedString(string: "\(req.tool)  ",
            attributes: [.foregroundColor: colors.coral,
                         .font: NSFont.boldSystemFont(ofSize: cfg.fonts.tool)]))
        s.append(NSAttributedString(string: sum,
            attributes: [.foregroundColor: colors.text,
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
        let colors = activeColors
        let h = bounds.height
        let cx = min(max(x, thumbW / 2), bounds.width - thumbW / 2)
        let th: CGFloat = 28
        thumb.frame = CGRect(x: cx - thumbW / 2, y: (h - th) / 2, width: thumbW, height: th)
        thumbArrow.frame = CGRect(x: 0, y: (th - 24) / 2, width: thumbW, height: 24)
        let mag = min(abs(dx) / threshold, 1)
        if dx > 6 {
            thumbArrow.string = "→"; thumb.backgroundColor = colors.green.cgColor
            layer?.backgroundColor = blend(colors.background, colors.green, mag * 0.9).cgColor
        } else if dx < -6 {
            thumbArrow.string = "←"; thumb.backgroundColor = colors.red.cgColor
            layer?.backgroundColor = blend(colors.background, colors.red, mag * 0.9).cgColor
        } else {
            thumbArrow.string = "↔"; thumb.backgroundColor = colors.coral.cgColor
            layer?.backgroundColor = colors.background.cgColor
        }
        thumb.transform = CATransform3DMakeScale(abs(dx) >= threshold ? 1.18 : 1.0,
                                                  abs(dx) >= threshold ? 1.18 : 1.0, 1)
    }
    private func reset() {
        thumb.opacity = 0; thumb.transform = CATransform3DIdentity
        layer?.backgroundColor = activeColors.background.cgColor
        text1.opacity = 1; text2.opacity = 1; activeIcon.opacity = 1
    }
    private func confirm(_ d: Decision) {
        let colors = activeColors
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let c = (d == .allow ? colors.green : colors.red)
        layer?.backgroundColor = c.withAlphaComponent(0.9).cgColor
        thumb.backgroundColor = c.cgColor
        CATransaction.commit()
        onDecision?(d)
    }
}
