import Cocoa

final class MainWindowController: NSWindowController, NSWindowDelegate {
    let scope = ScopeController()
    let screenView = ScreenView()
    private let statusView = StatusView(frame: .zero)
    private var statusLabel: NSTextField { return statusView.label }
    private let liveCheck = NSButton(checkboxWithTitle: "Live view", target: nil, action: nil)
    private let connectButton = KeyButton(frame: .zero)
    private let shotButton = KeyButton(frame: .zero)
    private let waveButton = KeyButton(frame: .zero)
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let canvas = LayoutCanvas(frame: .zero)
    private var connected = false
    private var keyButtons: [String: KeyButton] = [:]
    private var extraLabels: [NSTextField] = []
    private(set) var layout = Layout.builtIn
    var waveWindow: WaveWindowController?

    static let keyCodes: [String: Int32] = [
        "key.run": 0x0C, "key.auto": 0x17, "key.single": 0x10, "key.ch1": 0x06, "key.math": 0x0E,
        "key.measure": 0x02, "key.acquire": 0x1D, "key.display": 0x0D, "key.trigger": 0x11,
        "key.horizontal": 0x00, "key.record": 0x0F, "key.dso": 0x1C, "key.shift": 0x01,
        "key.select": 0x07, "key.ok": 0x16, "key.up": 0x12, "key.down": 0x13, "key.left": 0x14,
        "key.right": 0x15, "key.volts-v": 0x08, "key.volts-mv": 0x09, "key.time-s": 0x0A,
        "key.time-ns": 0x0B, "key.f1": 0x18, "key.f2": 0x19, "key.f3": 0x1A, "key.f4": 0x1B,
    ]

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "ScopeLink"
        super.init(window: w)
        w.delegate = self
        buildControls()
        apply(layout: Layout.loadCurrent(), resizeWindow: true)
        w.setFrameAutosaveName("MainWindow4")
        if w.setFrameUsingName("MainWindow4") {
            // keep the layout's proportions even if the saved window size came from another layout
            let cw = w.contentRect(forFrameRect: w.frame).width
            w.setContentSize(NSSize(width: cw, height: cw * layout.window.height / layout.window.width))
        } else { w.center() }
        wire()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: UI

    private func buildControls() {
        guard let content = window?.contentView else { return }
        canvas.frame = content.bounds
        canvas.autoresizingMask = [.width, .height]
        content.addSubview(canvas)

        connectButton.title = "Connect"
        connectButton.target = self
        connectButton.action = #selector(toggleConnect(_:))
        shotButton.title = "Save Screenshot…"
        shotButton.target = self
        shotButton.action = #selector(saveScreenshot(_:))
        waveButton.title = "Waveform…"
        waveButton.target = self
        waveButton.action = #selector(showWaveform(_:))
        liveCheck.target = self
        liveCheck.action = #selector(toggleLive(_:))
        modelPopup.addItems(withTitles: ["UTD1052DL (2 channels)", "UTD1025CL (1 channel)"])
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged(_:))
        modelPopup.toolTip = "Which model is connected; this sets the size of the waveform request"
        for (id, code) in MainWindowController.keyCodes {
            let b = KeyButton(frame: .zero)
            b.tag = Int(code)
            b.target = self
            b.action = #selector(keyPressed(_:))
            if let name = utd_key_name(code) { b.toolTip = "Sends the \(String(cString: name)) key to the scope" }
            keyButtons[id] = b
        }
    }

    private func view(for id: String) -> NSView? {
        switch id {
        case "connect": return connectButton
        case "live": return liveCheck
        case "screenshot": return shotButton
        case "waveform": return waveButton
        case "model": return modelPopup
        case "status": return statusView
        case "screen": return screenView
        default: return keyButtons[id]
        }
    }

    /// Places every control where the layout says. Controls the layout leaves out are hidden.
    func apply(layout l: Layout, resizeWindow: Bool) {
        layout = l
        for v in canvas.subviews { v.removeFromSuperview() }
        extraLabels.removeAll()
        let size = NSSize(width: l.window.width, height: l.window.height)
        canvas.designSize = size
        var placed = Set<String>()
        for it in l.items {
            let frame = NSRect(x: it.x, y: it.y, width: max(4, it.w), height: max(4, it.h))
            if it.type == "label" {
                let t = NSTextField(labelWithString: it.text ?? "")
                t.font = NSFont.systemFont(ofSize: it.size ?? 11, weight: (it.bold ?? false) ? .semibold : .regular)
                t.textColor = .secondaryLabelColor
                t.lineBreakMode = .byClipping
                // Keep the designed top-left corner, but never cut the text: the box grows to fit it.
                let fit = t.intrinsicContentSize
                t.frame = NSRect(x: frame.minX, y: frame.minY, width: max(frame.width, ceil(fit.width) + 6), height: max(frame.height, ceil(fit.height)))
                t.isHidden = it.hidden ?? false
                canvas.addSubview(t)
                extraLabels.append(t)
                continue
            }
            guard let v = view(for: it.id), !placed.contains(it.id) else { continue }
            placed.insert(it.id)
            v.frame = frame
            v.isHidden = it.hidden ?? false
            if let b = v as? KeyButton {
                if let t = it.label, !t.isEmpty, b !== connectButton { b.title = t }
                b.fill = KeyButton.colour(named: it.color)
                b.needsDisplay = true
            } else if v === liveCheck, let t = it.label, !t.isEmpty {
                liveCheck.title = t
            }
            canvas.addSubview(v)
        }
        // Anything the layout does not mention stays out of sight but keeps working from the menus.
        for id in ["connect", "live", "screenshot", "waveform", "model", "status", "screen"] + Array(keyButtons.keys) where !placed.contains(id) {
            view(for: id)?.isHidden = true
        }
        if let w = window {
            w.contentAspectRatio = size
            w.contentMinSize = NSSize(width: size.width * 0.5, height: size.height * 0.5)
            if resizeWindow { w.setContentSize(size) }
        }
        gLogSink?("Layout: \(l.name ?? "unnamed"), \(l.items.count) items, \(Int(size.width))×\(Int(size.height))")
    }

    private func wire() {
        let d = UserDefaults.standard
        scope.singleChannel = d.bool(forKey: "singleChannel")
        scope.paletteBGR = d.bool(forKey: "paletteBGR")
        scope.screenFormat = d.integer(forKey: "screenFormat")
        if d.object(forKey: "singleChannel") == nil { scope.singleChannel = true }  // UTD1025CL is the common case
        modelPopup.selectItem(at: scope.singleChannel ? 1 : 0)

        scope.onFrame = { [weak self] img, _ in self?.screenView.image = img }
        scope.onStatus = { [weak self] ok, msg in self?.setStatus(ok, msg) }
    }

    private func setStatus(_ ok: Bool, _ msg: String) {
        connected = ok
        statusLabel.stringValue = msg
        statusLabel.toolTip = msg
        statusView.dot.textColor = ok ? .systemGreen : .systemRed
        connectButton.title = ok ? "Disconnect" : "Connect"
        if !ok { screenView.placeholder = liveCheck.state == .on ? "Waiting for the oscilloscope…" : "Not connected" }
        if !ok && liveCheck.state == .off { screenView.image = nil }
    }

    /// Test frame through the real decoder (launch with --demo); used by the build to check drawing.
    func showDemoFrame() {
        var header = [UInt8](repeating: 0, count: 0xC0)
        header[0x40] = 0x55; header[0x41] = 0xAA
        // palette entries stored R,G,B, as the UTD1025CL sends them
        let palette: [[UInt8]] = [[0, 0, 0], [70, 70, 70], [255, 214, 40], [0, 200, 255], [230, 230, 230]]
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
            utd_decode_screen(hb.baseAddress, rb.baseAddress, Int32(rle.count), ob.baseAddress, 0)
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
        UserDefaults.standard.set(scope.paletteBGR, forKey: "paletteBGR")
        if connected && !isLive { scope.refreshScreen() }
    }

    @objc func setScreenFormat(_ sender: NSMenuItem) {
        scope.screenFormat = sender.tag
        UserDefaults.standard.set(sender.tag, forKey: "screenFormat")
        if connected && !isLive { scope.refreshScreen() }
    }

    @objc func loadLayout(_ sender: Any?) {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.message = "Choose a layout made with the ScopeLink Layout Designer"
        panel.beginSheetModal(for: w) { resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                let l = try Layout.parse(try Data(contentsOf: url))
                try l.saveAsCurrent()
                self.apply(layout: l, resizeWindow: true)
            } catch {
                self.alert("Could not load the layout", error.localizedDescription)
            }
        }
    }

    @objc func exportLayout(_ sender: Any?) {
        guard let w = window, let data = layout.encoded() else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = "\(layout.name ?? "layout").scopelink-layout.json"
        panel.beginSheetModal(for: w) { resp in
            guard resp == .OK, let url = panel.url else { return }
            do { try data.write(to: url) } catch { self.alert("Could not save", error.localizedDescription) }
        }
    }

    @objc func resetLayout(_ sender: Any?) {
        Layout.resetCurrent()
        apply(layout: Layout.builtIn, resizeWindow: true)
    }

    @objc func openDesigner(_ sender: Any?) {
        if let u = URL(string: "https://claude.ai/artifact/66mP8GDX1nkheiqmCBze2y") { NSWorkspace.shared.open(u) }
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
