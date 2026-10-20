import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var main: MainWindowController!
    let log = LogWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        gLogSink = { [weak self] line in self?.log.append(line) }
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        log.append("ScopeLink \(v) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        buildMenu()
        main = MainWindowController()
        main.showWindow(nil)
        main.window?.makeKeyAndOrderFront(nil)
        if CommandLine.arguments.contains("--demo") {
            main.showDemoFrame()
        } else {
            main.scope.connect()
            main.scope.refreshScreen()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSwap(_:)) { menuItem.state = main?.scope.paletteBGR == true ? .on : .off }
        if menuItem.action == #selector(toggleLiveMenu(_:)) { menuItem.state = main?.isLive == true ? .on : .off }
        if menuItem.action == #selector(setFormat(_:)) { menuItem.state = main?.scope.screenFormat == menuItem.tag ? .on : .off }
        return true
    }

    @objc func showLog(_ sender: Any?) { log.showWindow(nil) }
    @objc func setFormat(_ sender: NSMenuItem) { main.setScreenFormat(sender) }
    @objc func loadLayout(_ sender: Any?) { main.loadLayout(sender) }
    @objc func exportLayout(_ sender: Any?) { main.exportLayout(sender) }
    @objc func resetLayout(_ sender: Any?) { main.resetLayout(sender) }
    @objc func openDesigner(_ sender: Any?) { main.openDesigner(sender) }
    @objc func toggleSwap(_ sender: Any?) { main.toggleSwapColors(sender) }
    @objc func toggleLiveMenu(_ sender: Any?) { main.toggleLive(sender) }
    @objc func saveShot(_ sender: Any?) { main.saveScreenshot(sender) }
    @objc func showWave(_ sender: Any?) { main.showWaveform(sender) }
    @objc func connect(_ sender: Any?) { main.toggleConnect(sender) }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(string:
            "For UNI-T UTD1000-series handheld oscilloscopes (UTD1052DL, UTD1000CL) over USB.\n\n" +
            "Live screen, front-panel keys, screenshots and waveform export. " +
            "Firmware upgrade is deliberately not included.\n\n" +
            "Also included: the scopectl command-line tool (Contents/MacOS/scopectl).\n\n" +
            "Uses libusb (LGPL-2.1).",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.textColor])
        NSApp.orderFrontStandardAboutPanel(options: [NSApplication.AboutPanelOptionKey.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = self
        return i
    }

    private func buildMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let app = NSMenu()
        app.addItem(item("About ScopeLink", #selector(showAbout(_:)), ""))
        app.addItem(.separator())
        let hide = NSMenuItem(title: "Hide ScopeLink", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(hide)
        let others = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(others)
        app.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Quit ScopeLink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = app

        let fileItem = NSMenuItem(); bar.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(item("Connect / Disconnect", #selector(connect(_:)), "k"))
        file.addItem(item("Save Screenshot…", #selector(saveShot(_:)), "s"))
        file.addItem(item("Waveform…", #selector(showWave(_:)), "e"))
        file.addItem(.separator())
        file.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = file

        let editItem = NSMenuItem(); bar.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit

        let viewItem = NSMenuItem(); bar.addItem(viewItem)
        let view = NSMenu(title: "View")
        let live = item("Live View", #selector(toggleLiveMenu(_:)), "l")
        live.tag = 1
        view.addItem(live)
        view.addItem(item("Swap Red/Blue Colours", #selector(toggleSwap(_:)), ""))
        view.addItem(.separator())
        view.addItem(item("Load Layout…", #selector(loadLayout(_:)), "o"))
        view.addItem(item("Export Current Layout…", #selector(exportLayout(_:)), ""))
        view.addItem(item("Reset to Default Layout", #selector(resetLayout(_:)), ""))
        view.addItem(item("Open Layout Designer", #selector(openDesigner(_:)), ""))
        view.addItem(.separator())
        let fmtItem = NSMenuItem(title: "Screen Format", action: nil, keyEquivalent: "")
        let fmtMenu = NSMenu(title: "Screen Format")
        for (tag, title) in [(0, "Automatic"), (1, "UTD1000CL"), (2, "UTD1052DL")] {
            let i = NSMenuItem(title: title, action: #selector(setFormat(_:)), keyEquivalent: "")
            i.tag = tag
            i.target = self
            fmtMenu.addItem(i)
        }
        fmtItem.submenu = fmtMenu
        view.addItem(fmtItem)
        viewItem.submenu = view

        let winItem = NSMenuItem(); bar.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        win.addItem(item("Log", #selector(showLog(_:)), "l", [.command, .shift]))
        winItem.submenu = win
        NSApp.windowsMenu = win

        NSApp.mainMenu = bar
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
