import AppKit

/// 界面文案的中/英/日本地化。
enum L10n {
    static func deny(_ lang: String) -> String {
        switch lang { case "en": return "Deny"; case "ja": return "拒否"; default: return "拒绝" }
    }
    static func allow(_ lang: String) -> String {
        switch lang { case "en": return "Allow"; case "ja": return "許可"; default: return "通过" }
    }
}

/// "#RRGGBB" → NSColor，失败返回 nil。
func hexColor(_ s: String) -> NSColor? {
    var h = s.trimmingCharacters(in: .whitespaces)
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

/// 运行时配置。从 ~/.touchbar-cc/config.json 加载，缺项回退默认；文件不存在则写一份默认供编辑。
struct AppConfig {
    struct Colors { var background, text, coral, red, green: NSColor }
    struct Fonts { var session, tool, summary, hint: CGFloat }

    var language: String          // zh / en / ja
    var threshold: CGFloat        // 滑动触发距离
    var thumbWidth: CGFloat       // 滑块宽度
    var iconPath: String          // 自定义图标(PNG等)绝对路径；空则用内置 Claude 星芒
    var colors: Colors
    var fonts: Fonts
    var uiTimeoutExtra: CGFloat   // tbcd 当前项自动超时 = hook 超时 + 该余量

    /// 当前生效配置（main 启动时 load 后赋值）。
    static var current: AppConfig = .default

    static let `default` = AppConfig(
        language: "zh", threshold: 105, thumbWidth: 54, iconPath: "",
        colors: Colors(background: .black,
                       text: hexColor("#F0EEE6")!, coral: hexColor("#D97757")!,
                       red: hexColor("#D95B50")!, green: hexColor("#79B068")!),
        fonts: Fonts(session: 14, tool: 16, summary: 16, hint: 14),
        uiTimeoutExtra: 5)

    // 全 optional → 缺键解析为 nil 不抛错，逐项 merge 到默认值。
    private struct File: Codable {
        var language: String?
        var threshold: Double?
        var thumbWidth: Double?
        var iconPath: String?
        var uiTimeoutExtra: Double?
        var colors: C?
        var fonts: F?
        struct C: Codable { var background, text, coral, red, green: String? }
        struct F: Codable { var session, tool, summary, hint: Double? }
    }

    static func load() -> AppConfig {
        var c = AppConfig.default
        let dir = "\(NSHomeDirectory())/.touchbar-cc"
        let path = "\(dir)/config.json"
        let fm = FileManager.default

        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? defaultJSON.write(toFile: path, atomically: true, encoding: .utf8)
            return c
        }
        guard let data = fm.contents(atPath: path),
              let f = try? JSONDecoder().decode(File.self, from: data) else { return c }

        if let v = f.language { c.language = v }
        if let v = f.threshold { c.threshold = CGFloat(v) }
        if let v = f.thumbWidth { c.thumbWidth = CGFloat(v) }
        if let v = f.iconPath { c.iconPath = (v as NSString).expandingTildeInPath }
        if let v = f.uiTimeoutExtra { c.uiTimeoutExtra = CGFloat(v) }
        if let cc = f.colors {
            if let s = cc.background, let col = hexColor(s) { c.colors.background = col }
            if let s = cc.text, let col = hexColor(s) { c.colors.text = col }
            if let s = cc.coral, let col = hexColor(s) { c.colors.coral = col }
            if let s = cc.red, let col = hexColor(s) { c.colors.red = col }
            if let s = cc.green, let col = hexColor(s) { c.colors.green = col }
        }
        if let ff = f.fonts {
            if let v = ff.session { c.fonts.session = CGFloat(v) }
            if let v = ff.tool { c.fonts.tool = CGFloat(v) }
            if let v = ff.summary { c.fonts.summary = CGFloat(v) }
            if let v = ff.hint { c.fonts.hint = CGFloat(v) }
        }
        return c
    }

    static let defaultJSON = """
    {
      "language": "zh",
      "threshold": 105,
      "thumbWidth": 54,
      "iconPath": "",
      "uiTimeoutExtra": 5,
      "colors": {
        "background": "#000000",
        "text": "#F0EEE6",
        "coral": "#D97757",
        "red": "#D95B50",
        "green": "#79B068"
      },
      "fonts": { "session": 14, "tool": 16, "summary": 16, "hint": 14 }
    }
    """
}
