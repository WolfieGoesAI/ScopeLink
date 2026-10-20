import Foundation
import CoreGraphics

/// Receives log lines from the C core (any thread).
var gLogSink: ((String) -> Void)?
let cLogCallback: utd_log_fn = { _, line in
    guard let line = line else { return }
    let s = String(cString: line)
    DispatchQueue.main.async { gLogSink?(s) }
}

/// A captured waveform; owns the C buffer.
final class WaveCapture {
    let ptr: OpaquePointer
    init(ptr: OpaquePointer) { self.ptr = ptr }
    deinit { utd_wave_free(ptr) }

    var channelCount: Int { return Int(utd_wave_channels(ptr)) }
    var bytes: Int { return Int(utd_wave_bytes(ptr)) }
    func enabled(_ ch: Int) -> Bool { return utd_wave_enabled(ptr, Int32(ch)) != 0 }
    func voltsIndex(_ ch: Int) -> Int { return Int(utd_wave_volts_index(ptr, Int32(ch))) }
    func perColumn(_ ch: Int) -> Int { return Int(utd_wave_per_column(ptr, Int32(ch))) }
    func samples(_ ch: Int) -> [UInt8] {
        let n = Int(utd_wave_count(ptr, Int32(ch)))
        guard n > 0, let p = utd_wave_samples(ptr, Int32(ch)) else { return [] }
        return Array(UnsafeBufferPointer(start: p, count: n))
    }
    func writeCSV(to path: String) -> Bool { return utd_write_wave_csv(path, ptr) == 0 }
}

/// Owns the USB connection. All USB work runs on one serial queue; callbacks arrive on the main queue.
final class ScopeController {
    static let width = Int(UTD_SCREEN_W)
    static let height = Int(UTD_SCREEN_H)

    private let queue = DispatchQueue(label: "scopelink.usb")
    private var dev: OpaquePointer?          // queue only
    private var live = false                 // queue only
    private var liveGeneration = 0           // queue only
    private var lastStatus = ""              // queue only

    // Settings (written on main, read on queue; simple values)
    var singleChannel = false
    var paletteBGR = true
    var liveInterval: Double = 0.15

    var onFrame: ((CGImage, [UInt8]) -> Void)?
    var onStatus: ((Bool, String) -> Void)?

    init() {
        utd_set_log(cLogCallback, nil)
    }

    // MARK: public API (call from main)

    func connect() { queue.async { _ = self.openIfNeeded(force: true) } }

    func disconnect() {
        queue.async {
            self.live = false
            self.liveGeneration += 1
            self.closeDevice(message: "Disconnected")
        }
    }

    func setLive(_ on: Bool) {
        queue.async {
            self.liveGeneration += 1
            self.live = on
            if on { self.liveTick(self.liveGeneration) }
        }
    }

    func refreshScreen() {
        queue.async {
            guard self.openIfNeeded(force: false) else { return }
            self.captureAndPublish()
        }
    }

    func press(key: Int) {
        queue.async {
            guard self.openIfNeeded(force: false) else { return }
            let r = utd_press_key(self.dev, Int32(key))
            if r != 0 { self.fail(r); return }
            let name = utd_key_name(Int32(key)).map { String(cString: $0) } ?? String(key)
            self.log("Key \(name)")
            if !self.live {
                // Show the effect of the key press
                self.queue.asyncAfter(deadline: .now() + 0.35) {
                    if !self.live, self.dev != nil { self.captureAndPublish() }
                }
            }
        }
    }

    /// Captures a screenshot (raw RGB) for saving.
    func captureScreen(_ done: @escaping ([UInt8]?) -> Void) {
        queue.async {
            var result: [UInt8]? = nil
            if self.openIfNeeded(force: false) { result = self.captureAndPublish() }
            DispatchQueue.main.async { done(result) }
        }
    }

    func captureWave(_ done: @escaping (WaveCapture?) -> Void) {
        queue.async {
            var result: WaveCapture? = nil
            if self.openIfNeeded(force: false), let w = utd_wave_new() {
                let cap = WaveCapture(ptr: w)
                let model = self.singleChannel ? UTD_MODEL_1CH : UTD_MODEL_2CH
                let r = utd_capture_wave(self.dev, model, w)
                if r == 0 {
                    result = cap
                    self.log("Waveform: \(cap.bytes) bytes, \(cap.channelCount) channel block(s)")
                } else {
                    self.fail(r)
                }
            }
            DispatchQueue.main.async { done(result) }
        }
    }

    // MARK: queue internals

    private func log(_ s: String) { DispatchQueue.main.async { gLogSink?(s) } }

    private func status(_ connected: Bool, _ msg: String) {
        if msg == lastStatus { return }
        lastStatus = msg
        log(msg)
        DispatchQueue.main.async { self.onStatus?(connected, msg) }
    }

    private func openIfNeeded(force: Bool) -> Bool {
        if dev != nil { return true }
        var d: OpaquePointer? = nil
        let r = utd_open(&d)
        if r != 0 || d == nil {
            if force { lastStatus = "" }
            status(false, String(cString: utd_strerror(r)))
            return false
        }
        dev = d
        var buf = [CChar](repeating: 0, count: 256)
        utd_describe(d, &buf, buf.count)
        status(true, "Connected: " + String(cString: buf))
        return true
    }

    private func closeDevice(message: String) {
        if let d = dev { utd_close(d) }
        dev = nil
        status(false, message)
    }

    private func fail(_ err: Int32) {
        let msg = String(cString: utd_strerror(err))
        log("Error: \(msg)")
        // A failed transfer usually means the scope was unplugged or switched off; reopen next time.
        closeDevice(message: "Connection lost – \(msg)")
    }

    @discardableResult
    private func captureAndPublish() -> [UInt8]? {
        guard dev != nil else { return nil }
        var rgb = [UInt8](repeating: 0, count: ScopeController.width * ScopeController.height * 3)
        let bgr: Int32 = paletteBGR ? 1 : 0
        let d = dev
        let r = rgb.withUnsafeMutableBufferPointer { buf -> Int32 in
            return utd_capture_screen(d, buf.baseAddress, bgr)
        }
        if r != 0 { fail(r); return nil }
        if let img = ScopeController.makeImage(rgb) {
            DispatchQueue.main.async { self.onFrame?(img, rgb) }
        }
        return rgb
    }

    private func liveTick(_ gen: Int) {
        guard live, gen == liveGeneration else { return }
        if openIfNeeded(force: false) {
            captureAndPublish()
            queue.asyncAfter(deadline: .now() + liveInterval) { self.liveTick(gen) }
        } else {
            // Keep trying until the scope is plugged in
            queue.asyncAfter(deadline: .now() + 2.0) { self.liveTick(gen) }
        }
    }

    static func makeImage(_ rgb: [UInt8]) -> CGImage? {
        let data = Data(rgb) as CFData
        guard let provider = CGDataProvider(data: data),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                       bytesPerRow: width * 3, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
