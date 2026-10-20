import Cocoa

final class MainWindowController: NSWindowController, NSWindowDelegate {
    let scope = ScopeController()
    let screenView = ScreenView()
    private let statusLabel = NSTextField(labelWithString: "Not connected")
    private let statusDot = NSTextField(labelWithString: "●")
    private let liveCheck = NSButton(checkboxWithTitle: "Live view", target: nil, action: nil)
    private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var connected = false
    private var keyButtons: [NSButton] = []
    var waveWindow: WaveWindowController?

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "ScopeLink"
        w.minSize = NSSize(width: 1000, height: 480)
        super.init(window: w)
        w.delegate = self
        buildUI()
        w.setFrameAutosaveName("MainWindow2")
        if !w.setFrameUsingName("MainWindow2") { w.center() }
        wire()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: UI

    private func keyButton(_ title: String, _ key: Int32, width: CGFloat = 92) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(keyPressed(_:)))
        b.tag = Int(key)
        b.bezelStyle = .rounded
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: width).isActive = true
        if let name = utd_key_name(key) { b.toolTip = "Sends the \(String(cString: name)) key to the scope" }
        keyButtons.append(b)
        return b
    }

    private func sectionLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Top bar
        connectButton.target = self
        connectButton.action = #selector(toggleConnect(_:))
        connectButton.bezelStyle = .rounded
        liveCheck.target = self
        liveCheck.action = #selector(toggleLive(_:))
        let shotButton = NSButton(title: "Save Screenshot…", target: self, action: #selector(saveScreenshot(_:)))
        let waveButton = NSButton(title: "Waveform…", target: self, action: #selector(showWaveform(_:)))
        modelPopup.addItems(withTitles: ["UTD1052DL (2 channels)", "UTD1000CL (1 channel)"])
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))
        modelPopup.toolTip = "Which model is connected; this sets the size of the waveform request"
        statusDot.textColor = .systemRed
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let top = NSStackView(views: [connectButton, liveCheck, shotButton, waveButton, modelPopup, statusDot, statusLabel])
        top.orientation = .horizontal
        top.spacing = 10
        top.setCustomSpacing(4, after: statusDot)

        // Screen + F1–F4 (the scope has its menu keys beside the screen)
        screenView.translatesAutoresizingMaskIntoConstraints = false
        screenView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        screenView.setContentHuggingPriority(.defaultLow, for: .vertical)
        screenView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        screenView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        screenView.widthAnchor.constraint(equalTo: screenView.heightAnchor, multiplier: 4.0 / 3.0).isActive = true
        screenView.widthAnchor.constraint(greaterThanOrEqualToConstant: 480).isActive = true
        let fKeys = NSStackView(views: [keyButton("F1", 0x18, width: 56), keyButton("F2", 0x19, width: 56),
                                        keyButton("F3", 0x1A, width: 56), keyButton("F4", 0x1B, width: 56)])
        fKeys.orientation = .vertical
        fKeys.distribution = .equalSpacing
        fKeys.spacing = 40

        // Front panel
        let grid = NSGridView(views: [
            [keyButton("Run/Stop", 0x0C), keyButton("Auto", 0x17), keyButton("Single", 0x10)],
            [keyButton("CH1", 0x06), keyButton("Math", 0x0E), keyButton("Measure", 0x02)],
            [keyButton("Acquire", 0x1D), keyButton("Display", 0x0D), keyButton("Trigger", 0x11)],
            [keyButton("Horizontal", 0x00), keyButton("Record", 0x0F), keyButton("DSO/DMM", 0x1C)],
            [keyButton("Shift", 0x01), keyButton("Select", 0x07), keyButton("OK", 0x16)],
        ])
        grid.rowSpacing = 4
        grid.columnSpacing = 6
        // Arrow cross: four buttons placed explicitly in a fixed-size box
        let arrows = NSView()
        arrows.translatesAutoresizingMaskIntoConstraints = false
        let up = keyButton("▲", 0x12, width: 50), down = keyButton("▼", 0x13, width: 50)
        let left = keyButton("◀", 0x14, width: 50), right = keyButton("▶", 0x15, width: 50)
        for b in [up, down, left, right] { arrows.addSubview(b) }
        NSLayoutConstraint.activate([
            arrows.widthAnchor.constraint(equalToConstant: 160),
            arrows.heightAnchor.constraint(equalToConstant: 80),
            up.centerXAnchor.constraint(equalTo: arrows.centerXAnchor),
            up.topAnchor.constraint(equalTo: arrows.topAnchor),
            down.centerXAnchor.constraint(equalTo: arrows.centerXAnchor),
            down.bottomAnchor.constraint(equalTo: arrows.bottomAnchor),
            left.leadingAnchor.constraint(equalTo: arrows.leadingAnchor),
            left.centerYAnchor.constraint(equalTo: arrows.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: arrows.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: arrows.centerYAnchor),
        ])
        let volts = NSStackView(views: [keyButton("V", 0x08, width: 60), keyButton("mV", 0x09, width: 60)])
        let time = NSStackView(views: [keyButton("s", 0x0A, width: 60), keyButton("ns", 0x0B, width: 60)])
        let panel = NSStackView(views: [sectionLabel("FRONT PANEL"), grid,
                                        sectionLabel("CURSOR / POSITION"), arrows,
                                        sectionLabel("VOLTS/DIV"), volts,
                                        sectionLabel("TIME/DIV"), time])
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 6
        panel.setCustomSpacing(14, after: grid)
        panel.setCustomSpacing(14, after: arrows)
        panel.setCustomSpacing(14, after: volts)

        // Explicit layout: top bar, then screen | F-keys | panel. The screen keeps 4:3 and
        // takes the window's height; the panel keeps its natural size.
        for v in [top, fKeys, panel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        content.addSubview(screenView)
        top.setHuggingPriority(.required, for: .vertical)
        panel.setHuggingPriority(.required, for: .vertical)
        panel.setHuggingPriority(.required, for: .horizontal)
        // The screen is the part that gives way when the window is small.
        let screenBottom = screenView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        screenBottom.priority = NSLayoutConstraint.Priority(rawValue: 600)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            top.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),

            screenView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            screenView.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12),
            screenView.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -14),
            screenBottom,

            fKeys.leadingAnchor.constraint(equalTo: screenView.trailingAnchor, constant: 12),
            fKeys.centerYAnchor.constraint(equalTo: screenView.centerYAnchor),
            fKeys.heightAnchor.constraint(equalTo: screenView.heightAnchor, multiplier: 0.8),

            panel.leadingAnchor.constraint(equalTo: fKeys.trailingAnchor, constant: 16),
            panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 3 * 92 + 2 * 6),
            panel.topAnchor.constraint(equalTo: screenView.topAnchor),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -14),
        ])
    }

    private func wire() {
        let d = UserDefaults.standard
        scope.singleChannel = d.bool(forKey: "singleChannel")
        scope.paletteBGR = !d.bool(forKey: "paletteRGB")
        scope.screenFormat = d.integer(forKey: "screenFormat")
        modelPopup.selectItem(at: scope.singleChannel ? 1 : 0)

        scope.onFrame = { [weak self] img, _ in self?.screenView.image = img }
        scope.onStatus = { [weak self] ok, msg in self?.setStatus(ok, msg) }
    }

    private func setStatus(_ ok: Bool, _ msg: String) {
        connected = ok
        statusLabel.stringValue = msg
        statusLabel.toolTip = msg
        statusDot.textColor = ok ? .systemGreen : .systemRed
        connectButton.title = ok ? "Disconnect" : "Connect"
        if !ok { screenView.placeholder = liveCheck.state == .on ? "Waiting for the oscilloscope…" : "Not connected" }
        if !ok && liveCheck.state == .off { screenView.image = nil }
    }

    /// Test frame through the real decoder (launch with --demo); used by the build to check drawing.
    func showDemoFrame() {
        var header = [UInt8](repeating: 0, count: 0xC0)
        header[0x40] = 0x55; header[0x41] = 0xAA
        // palette entries stored B,G,R like the Windows app expects
        let palette: [[UInt8]] = [[0, 0, 0], [70, 70, 70], [40, 214, 255], [255, 200, 0], [230, 230, 230]]
        for (i, e) in palette.enumerated() { for j in 0..<3 { header[0x44 + 3 * i + j] = e[j] } }
        var rle: [UInt8] = []
        func emit(_ c: Int, _ n: Int) {
            var n = n
            while n > 0 { let r = min(n, 2047); rle.append(UInt8((c & 0x1F) | ((r & 7) << 5))); rle.append(UInt8(r >> 3)); n -= r }
        }
        let w = ScopeController.width, h = ScopeController.height
        for x in 0..<w {
            var col = [Int](repeating: 0, count: h)
            for y in 0..<h {
                if y < 14 || y >= h - 14 { col[y] = 4 } else if x % 30 == 10 || (y - 14) % 26 == 0 { col[y] = 1 }
            }
            let t = Double(x) / Double(w) * 4 * Double.pi
            let y1 = Int(120 - 70 * sin(t)), y2 = Int(150 - 40 * cos(t * 0.5))
            for d in -1...1 { if y1 + d >= 0 && y1 + d < h { col[y1 + d] = 2 }; if y2 + d >= 0 && y2 + d < h { col[y2 + d] = 3 } }
            var run = 1
            for y in 1...h {
                if y < h && col[y] == col[y - 1] { run += 1 } else { emit(col[y - 1], run); run = 1 }
            }
        }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        header.withUnsafeBufferPointer { hb in rle.withUnsafeBufferPointer { rb in rgb.withUnsafeMutableBufferPointer { ob in
            utd_decode_screen(hb.baseAddress, rb.baseAddress, Int32(rle.count), ob.baseAddress, 1)
        } } }
        screenView.image = ScopeController.makeImage(rgb)
        statusLabel.stringValue = "Demo frame (\(rle.count) bytes of run-length data decoded)"
    }

    // MARK: actions

    @objc func toggleConnect(_ sender: Any?) {
        if connected {
            liveCheck.state = .off
            scope.disconnect()
        } else {
            scope.connect()
            scope.refreshScreen()
        }
    }

    @objc func toggleLive(_ sender: Any?) {
        if let b = sender as? NSMenuItem, b.tag == 1 { liveCheck.state = liveCheck.state == .on ? .off : .on }
        let on = liveCheck.state == .on
        if on && !connected { screenView.placeholder = "Waiting for the oscilloscope…" }
        scope.setLive(on)
    }

    var isLive: Bool { return liveCheck.state == .on }

    @objc func keyPressed(_ sender: NSButton) {
        scope.press(key: sender.tag)
    }

    @objc func modelChanged(_ sender: Any?) {
        scope.singleChannel = modelPopup.indexOfSelectedItem == 1
        UserDefaults.standard.set(scope.singleChannel, forKey: "singleChannel")
    }

    @objc func toggleSwapColors(_ sender: Any?) {
        scope.paletteBGR.toggle()
        UserDefaults.standard.set(!scope.paletteBGR, forKey: "paletteRGB")
        if connected && !isLive { scope.refreshScreen() }
    }

    @objc func setScreenFormat(_ sender: NSMenuItem) {
        scope.screenFormat = sender.tag
        UserDefaults.standard.set(sender.tag, forKey: "screenFormat")
        if connected && !isLive { scope.refreshScreen() }
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    @objc func saveScreenshot(_ sender: Any?) {
        scope.captureScreen { [weak self] rgb in
            guard let self = self, let window = self.window else { return }
            guard let rgb = rgb else {
                self.alert("No screenshot", "The oscilloscope is not connected or did not answer.")
                return
            }
            let panel = NSSavePanel()
            panel.allowedFileTypes = ["png"]
            panel.nameFieldStringValue = "scope-\(MainWindowController.timestamp()).png"
            panel.beginSheetModal(for: window) { resp in
                guard resp == .OK, let url = panel.url else { return }
                let ok = rgb.withUnsafeBufferPointer { b -> Bool in
                    return utd_write_png(url.path, b.baseAddress, Int32(ScopeController.width), Int32(ScopeController.height)) == 0
                }
                gLogSink?(ok ? "Saved \(url.path)" : "Could not save \(url.path)")
                if !ok { self.alert("Could not save", url.path) }
            }
        }
    }

    @objc func showWaveform(_ sender: Any?) {
        if waveWindow == nil { waveWindow = WaveWindowController(scope: scope) }
        waveWindow?.showWindow(nil)
        waveWindow?.capture(nil)
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        if let w = window { a.beginSheetModal(for: w, completionHandler: nil) } else { a.runModal() }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

final class WaveWindowController: NSWindowController {
    private let scope: ScopeController
    private let view = WaveView()
    private var last: WaveCapture?
    private let info = NSTextField(labelWithString: "")

    init(scope: ScopeController) {
        self.scope = scope
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: true)
        w.title = "Waveform"
        super.init(window: w)
        w.setFrameAutosaveName("WaveWindow")
        let captureButton = NSButton(title: "Capture", target: self, action: #selector(capture(_:)))
        captureButton.keyEquivalent = "\r"
        let saveButton = NSButton(title: "Save CSV…", target: self, action: #selector(saveCSV(_:)))
        info.textColor = .secondaryLabelColor
        info.lineBreakMode = .byTruncatingTail
        let bar = NSStackView(views: [captureButton, saveButton, info])
        bar.spacing = 10
        view.translatesAutoresizingMaskIntoConstraints = false
        let root = NSStackView(views: [bar, view])
        root.orientation = .vertical
        root.alignment = .leading
        root.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        let c = w.contentView!
        c.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            root.topAnchor.constraint(equalTo: c.topAnchor),
            root.bottomAnchor.constraint(equalTo: c.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        if !w.setFrameUsingName("WaveWindow") { w.center() }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func capture(_ sender: Any?) {
        info.stringValue = "Capturing…"
        scope.captureWave { [weak self] cap in
            guard let self = self else { return }
            guard let cap = cap else {
                self.info.stringValue = "No waveform – the oscilloscope is not connected or did not answer."
                return
            }
            self.last = cap
            var chans: [[UInt8]] = [], labels: [String] = []
            for k in 0..<cap.channelCount {
                chans.append(cap.samples(k))
                labels.append("CH\(k + 1) \(cap.enabled(k) ? "on" : "off")  volts idx \(cap.voltsIndex(k))  \(cap.samples(k).count) samples")
            }
            self.view.channels = chans
            self.view.labels = labels
            self.info.stringValue = "\(cap.bytes) bytes received at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)). Raw codes 0–255; scaling to volts is not decoded yet."
        }
    }

    @objc func saveCSV(_ sender: Any?) {
        guard let cap = last, let w = window else {
            info.stringValue = "Capture a waveform first."
            return
        }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["csv"]
        panel.nameFieldStringValue = "wave-\(MainWindowController.timestamp()).csv"
        panel.beginSheetModal(for: w) { resp in
            guard resp == .OK, let url = panel.url else { return }
            let ok = cap.writeCSV(to: url.path)
            gLogSink?(ok ? "Saved \(url.path)" : "Could not save \(url.path)")
            self.info.stringValue = ok ? "Saved \(url.lastPathComponent)" : "Could not save \(url.path)"
        }
    }
}
