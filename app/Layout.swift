import Cocoa

/// A ScopeLink layout template (made with the Layout Designer). Coordinates are points,
/// origin top-left of the window's content area.
struct LayoutItem: Codable {
    var id: String
    var type: String?
    var label: String?
    var text: String?
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var hidden: Bool?
    var color: String?
    var size: CGFloat?
    var bold: Bool?
}

struct LayoutWindow: Codable {
    var width: CGFloat
    var height: CGFloat
}

struct Layout: Codable {
    var format: String
    var version: Int
    var name: String?
    var window: LayoutWindow
    var items: [LayoutItem]

    enum LayoutError: LocalizedError {
        case notALayout, badSize
        var errorDescription: String? {
            switch self {
            case .notALayout: return "This file is not a ScopeLink layout (made with the Layout Designer)."
            case .badSize: return "The layout's window size is out of range."
            }
        }
    }

    static func parse(_ data: Data) throws -> Layout {
        let l = try JSONDecoder().decode(Layout.self, from: data)
        guard l.format == "scopelink-layout" else { throw LayoutError.notALayout }
        guard l.window.width >= 300, l.window.width <= 4000, l.window.height >= 200, l.window.height <= 3000 else { throw LayoutError.badSize }
        return l
    }

    func encoded() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        return try? e.encode(self)
    }

    static var builtIn: Layout {
        if let url = Bundle.main.url(forResource: "default-layout", withExtension: "json"),
           let data = try? Data(contentsOf: url), let l = try? Layout.parse(data) { return l }
        return Layout(format: "scopelink-layout", version: 1, name: "Minimal", window: LayoutWindow(width: 760, height: 600),
                      items: [LayoutItem(id: "connect", type: nil, label: "Connect", text: nil, x: 14, y: 10, w: 90, h: 26, hidden: nil, color: nil, size: nil, bold: nil),
                              LayoutItem(id: "live", type: nil, label: "Live view", text: nil, x: 112, y: 10, w: 96, h: 26, hidden: nil, color: nil, size: nil, bold: nil),
                              LayoutItem(id: "status", type: nil, label: nil, text: nil, x: 214, y: 10, w: 530, h: 26, hidden: nil, color: nil, size: nil, bold: nil),
                              LayoutItem(id: "screen", type: nil, label: nil, text: nil, x: 14, y: 46, w: 720, h: 540, hidden: nil, color: nil, size: nil, bold: nil)])
    }

    /// The user's saved layout lives in ~/Library/Application Support/ScopeLink/layout.json
    static var userFile: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("ScopeLink", isDirectory: true).appendingPathComponent("layout.json")
    }

    static func loadCurrent() -> Layout {
        if let f = userFile, let data = try? Data(contentsOf: f), let l = try? Layout.parse(data) { return l }
        return builtIn
    }

    func saveAsCurrent() throws {
        guard let f = Layout.userFile, let data = encoded() else { return }
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: f, options: .atomic)
    }

    static func resetCurrent() {
        if let f = userFile { try? FileManager.default.removeItem(at: f) }
    }
}

/// Holds the controls at their designed positions; scales with the window.
final class LayoutCanvas: NSView {
    var designSize = NSSize(width: 1120, height: 600) { didSet { updateScale() } }
    override var isFlipped: Bool { return true }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateScale()
    }
    private func updateScale() {
        guard frame.width > 0, frame.height > 0 else { return }
        setBoundsSize(designSize)
        needsDisplay = true
    }
}

/// Front-panel key drawn like the designer shows it: any size, optional colour.
final class KeyButton: NSButton {
    var fill: NSColor?

    static func colour(named n: String?) -> NSColor? {
        switch n ?? "" {
        case "red": return NSColor(srgbRed: 0.90, green: 0.33, blue: 0.29, alpha: 1)
        case "green": return NSColor(srgbRed: 0.25, green: 0.64, blue: 0.30, alpha: 1)
        case "yellow": return NSColor(srgbRed: 0.91, green: 0.72, blue: 0.18, alpha: 1)
        case "blue": return NSColor(srgbRed: 0.24, green: 0.50, blue: 0.88, alpha: 1)
        case "grey": return NSColor(srgbRed: 0.56, green: 0.58, blue: 0.60, alpha: 1)
        case "black": return NSColor(srgbRed: 0.17, green: 0.18, blue: 0.20, alpha: 1)
        default: return nil
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    private var isDark: Bool {
        if #available(macOS 10.14, *) {
            return effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        return false
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        var bg = fill ?? (isDark ? NSColor(white: 0.36, alpha: 1) : NSColor.white)
        if isHighlighted { bg = bg.blended(withFraction: 0.25, of: isDark ? .white : .black) ?? bg }
        bg.setFill()
        path.fill()
        (isDark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.22)).setStroke()
        path.lineWidth = 1
        path.stroke()
        var textColor = NSColor.controlTextColor
        if let f = fill?.usingColorSpace(.sRGB) {
            let lum = 0.299 * f.redComponent + 0.587 * f.greenComponent + 0.114 * f.blueComponent
            textColor = lum > 0.6 ? .black : .white
        }
        let size = min(13, max(9, bounds.height * 0.5))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: textColor, .paragraphStyle: para]
        let s = NSAttributedString(string: title, attributes: attrs)
        let h = s.size().height
        s.draw(in: NSRect(x: 3, y: (bounds.height - h) / 2, width: bounds.width - 6, height: h))
    }
}

/// Status dot + text in one box.
final class StatusView: NSView {
    let dot = NSTextField(labelWithString: "●")
    let label = NSTextField(labelWithString: "Not connected")
    override var isFlipped: Bool { return true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        dot.textColor = .systemRed
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(dot)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let dh = dot.intrinsicContentSize.height, lh = label.intrinsicContentSize.height
        dot.frame = NSRect(x: 0, y: (bounds.height - dh) / 2, width: 14, height: dh)
        label.frame = NSRect(x: 16, y: (bounds.height - lh) / 2, width: max(0, bounds.width - 16), height: lh)
    }
}
