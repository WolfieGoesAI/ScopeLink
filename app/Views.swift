import Cocoa

/// Shows the scope's 320×240 screen, scaled with sharp pixels.
final class ScreenView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    var placeholder = "Not connected" { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { return NSSize(width: 640, height: 480) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let img = image {
            let scale = min(bounds.width / CGFloat(img.width), bounds.height / CGFloat(img.height))
            let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
            let r = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
            ctx.interpolationQuality = scale >= 1 && scale == scale.rounded() ? .none : .medium
            ctx.draw(img, in: r)
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor(white: 0.6, alpha: 1),
            ]
            let s = NSAttributedString(string: placeholder, attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
        }
    }
}

/// Plots raw waveform codes (0–255) for each channel.
final class WaveView: NSView {
    var channels: [[UInt8]] = [] { didSet { needsDisplay = true } }
    var labels: [String] = [] { didSet { needsDisplay = true } }
    static let colors: [NSColor] = [NSColor(calibratedRed: 1, green: 0.85, blue: 0.1, alpha: 1),
                                    NSColor(calibratedRed: 0.2, green: 0.8, blue: 1, alpha: 1)]

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 1).setFill()
        bounds.fill()
        let plot = bounds.insetBy(dx: 10, dy: 24)
        // grid: 10 x 8 divisions
        NSColor(white: 0.3, alpha: 1).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        for i in 0...10 {
            let x = plot.minX + plot.width * CGFloat(i) / 10
            grid.move(to: NSPoint(x: x, y: plot.minY)); grid.line(to: NSPoint(x: x, y: plot.maxY))
        }
        for i in 0...8 {
            let y = plot.minY + plot.height * CGFloat(i) / 8
            grid.move(to: NSPoint(x: plot.minX, y: y)); grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        grid.stroke()
        for (k, s) in channels.enumerated() where s.count > 1 {
            let path = NSBezierPath()
            path.lineWidth = 1
            for (i, v) in s.enumerated() {
                let x = plot.minX + plot.width * CGFloat(i) / CGFloat(s.count - 1)
                let y = plot.minY + plot.height * CGFloat(v) / 255
                if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
            }
            WaveView.colors[k % 2].setStroke()
            path.stroke()
        }
        var x: CGFloat = 12
        for (k, l) in labels.enumerated() {
            let a = NSAttributedString(string: l, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: WaveView.colors[k % 2]])
            a.draw(at: NSPoint(x: x, y: bounds.maxY - 18))
            x += a.size().width + 24
        }
        if channels.isEmpty {
            let a = NSAttributedString(string: "No waveform captured yet", attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.6, alpha: 1)])
            let sz = a.size()
            a.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
        }
    }
}

/// Simple log window.
final class LogWindowController: NSWindowController {
    private let textView = NSTextView()
    private let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: true)
        w.title = "ScopeLink Log"
        w.setFrameAutosaveName("LogWindow")
        super.init(window: w)
        let scroll = NSScrollView(frame: w.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        textView.frame = scroll.bounds
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.font = NSFont.userFixedPitchFont(ofSize: 11)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        scroll.documentView = textView
        w.contentView!.addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }

    func append(_ line: String) {
        let s = "\(formatter.string(from: Date()))  \(line)\n"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.textColor]
        textView.textStorage?.append(NSAttributedString(string: s, attributes: attrs))
        textView.scrollToEndOfDocument(nil)
    }
}
