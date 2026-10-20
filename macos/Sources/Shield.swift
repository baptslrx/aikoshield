import AppKit
import CoreMedia
import ScreenCaptureKit
import Vision

/// Une zone masquée, en coordonnées globales de l'écran (points, origine en bas à gauche).
struct Mask: Equatable {
    enum Style: Equatable { case text, notification, window }
    var rect: CGRect
    var label: String
    var style: Style
    var seen: Date
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

// MARK: - Capture d'un écran

/// Reçoit les images d'un écran (ScreenCaptureKit), les lit avec Vision et renvoie les zones sensibles.
final class DisplayCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    struct Options { var precise: Bool; var enabled: Set<Category> }

    let displayID: CGDirectDisplayID
    let queue = DispatchQueue(label: "fr.aikographic.aikoshield.capture", qos: .userInitiated)
    var stream: SCStream?
    private let lock = NSLock()
    private var _options: Options
    private let onDetections: (CGDirectDisplayID, [Detection], Double) -> Void
    private let onStop: (Error) -> Void

    var options: Options {
        get { lock.lock(); defer { lock.unlock() }; return _options }
        set { lock.lock(); _options = newValue; lock.unlock() }
    }

    init(displayID: CGDirectDisplayID, options: Options,
         onDetections: @escaping (CGDirectDisplayID, [Detection], Double) -> Void,
         onStop: @escaping (Error) -> Void) {
        self.displayID = displayID
        self._options = options
        self.onDetections = onDetections
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let pixels = sampleBuffer.imageBuffer else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        let opts = options
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:])
        let found = Recognizer.detect(in: handler, precise: opts.precise, enabled: opts.enabled)
        onDetections(displayID, found, CFAbsoluteTimeGetCurrent() - t0)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop(error)
    }
}

// MARK: - Calque des masques (une fenêtre transparente par écran)

@MainActor
final class MaskView: NSView {
    var masks: [Mask] = [] { didSet { if masks != oldValue { needsDisplay = true } } }
    var showLabels = true

    override var isFlipped: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = Theme.isDark(effectiveAppearance)
        let fill = Theme.maskFill(dark: dark)
        let ink = Theme.maskInk(dark: dark)
        for m in masks {
            let r = m.rect.integral
            let radius = min(m.style == .text ? 5 : 12, r.height / 3)
            let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            fill.setFill()
            path.fill()
            ink.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 1
            path.stroke()
            guard showLabels else { continue }

            switch m.style {
            case .text:
                guard r.height >= 11, r.width >= 34 else { continue }
                let size = max(8, min(13, r.height * 0.55))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: ink,
                ]
                var text = "\(m.label) masqué"
                if (text as NSString).size(withAttributes: attrs).width > r.width - 8 { text = "masqué" }
                let s = (text as NSString).size(withAttributes: attrs)
                guard s.width <= r.width - 4 else { continue }
                (text as NSString).draw(at: NSPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2),
                                        withAttributes: attrs)
            case .notification, .window:
                guard r.height >= 40, r.width >= 120 else { continue }
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: ink,
                ]
                let config = NSImage.SymbolConfiguration(pointSize: m.style == .window ? 30 : 18, weight: .medium)
                    .applying(.init(paletteColors: [ink]))
                let icon = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
                let text = m.label as NSString
                let ts = text.size(withAttributes: titleAttrs)
                if m.style == .window, let icon {
                    let total = icon.size.height + 10 + ts.height
                    let top = r.midY + total / 2
                    icon.draw(in: NSRect(x: r.midX - icon.size.width / 2, y: top - icon.size.height,
                                         width: icon.size.width, height: icon.size.height))
                    text.draw(at: NSPoint(x: r.midX - ts.width / 2, y: top - icon.size.height - 10 - ts.height),
                              withAttributes: titleAttrs)
                } else {
                    let iw = icon?.size.width ?? 0
                    let total = iw + 8 + ts.width
                    let x = r.midX - total / 2
                    icon?.draw(in: NSRect(x: x, y: r.midY - (icon?.size.height ?? 0) / 2,
                                          width: iw, height: icon?.size.height ?? 0))
                    text.draw(at: NSPoint(x: x + iw + 8, y: r.midY - ts.height / 2), withAttributes: titleAttrs)
                }
            }
        }
    }
}

@MainActor
final class MaskOverlay {
    let window: NSPanel
    let view = MaskView()

    init(screen: NSScreen) {
        window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
    }

    func close() { window.orderOut(nil); window.close() }
}

// MARK: - Le bouclier

@MainActor
final class Shield {
    private(set) var isOn = false
    private(set) var lastError: String?
    var onChange: (() -> Void)?

    let settings: ShieldSettings
    private var captures: [DisplayCapture] = []
    private var overlays: [CGDirectDisplayID: MaskOverlay] = [:]
    private var textMasks: [CGDirectDisplayID: [Mask]] = [:]
    private var windowMasks: [Mask] = []
    private var timer: Timer?
    private var bundleCache: [pid_t: String] = [:]
    private var screenObserver: Any?
    private(set) var lastOCRSeconds: [CGDirectDisplayID: Double] = [:]
    private(set) var diagnosticWindows: [String] = []
    private let hold: TimeInterval = 1.5

    init(settings: ShieldSettings) {
        self.settings = settings
    }

    var maskedCount: Int { textMasks.values.reduce(0) { $0 + $1.count } + windowMasks.count }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func toggle() async {
        if isOn { stop() } else { await start() }
    }

    @discardableResult
    func start() async -> Bool {
        guard !isOn else { return true }
        lastError = nil
        guard Self.hasPermission else {
            lastError = "permission"
            onChange?()
            return false
        }
        // Les calques d'abord : ils doivent exister pour être exclus de notre propre capture
        for screen in NSScreen.screens {
            overlays[screen.displayID] = MaskOverlay(screen: screen)
        }
        refreshLabels()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let pid = ProcessInfo.processInfo.processIdentifier
            let me = content.applications.filter { $0.processID == pid }
            let myWindows = content.windows.filter { $0.owningApplication?.processID == pid }
            let opts = DisplayCapture.Options(precise: settings.precise, enabled: settings.categories)
            for display in content.displays {
                guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
                let filter = me.isEmpty
                    ? SCContentFilter(display: display, excludingWindows: myWindows)
                    : SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
                let config = SCStreamConfiguration()
                var scale = screen.backingScaleFactor
                if CGFloat(display.width) * scale > 4096 { scale = 4096 / CGFloat(display.width) }
                config.width = Int(CGFloat(display.width) * scale)
                config.height = Int(CGFloat(display.height) * scale)
                config.minimumFrameInterval = CMTime(value: 1, timescale: settings.precise ? 3 : 6)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.queueDepth = 3

                let capture = DisplayCapture(displayID: display.displayID, options: opts,
                    onDetections: { [weak self] id, found, seconds in
                        Task { @MainActor in self?.received(id, found, seconds) }
                    },
                    onStop: { [weak self] error in
                        Task { @MainActor in self?.streamStopped(error) }
                    })
                let stream = SCStream(filter: filter, configuration: config, delegate: capture)
                try stream.addStreamOutput(capture, type: .screen, sampleHandlerQueue: capture.queue)
                try await stream.startCapture()
                capture.stream = stream
                captures.append(capture)
            }
        } catch {
            lastError = error.localizedDescription
            stop()
            onChange?()
            return false
        }

        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanWindows() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOn else { return }
                Task { await self.restart() }
            }
        }
        isOn = true
        scanWindows()
        onChange?()
        return true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for c in captures {
            let s = c.stream
            Task { try? await s?.stopCapture() }
        }
        captures.removeAll()
        overlays.values.forEach { $0.close() }
        overlays.removeAll()
        textMasks.removeAll()
        windowMasks.removeAll()
        let wasOn = isOn
        isOn = false
        if wasOn { onChange?() }
    }

    /// À appeler quand un réglage change : relance proprement la capture.
    func restart() async {
        guard isOn else { return }
        stop()
        await start()
    }

    func refreshLabels() {
        overlays.values.forEach { $0.view.showLabels = settings.showLabels; $0.view.needsDisplay = true }
    }

    private func streamStopped(_ error: Error) {
        guard isOn else { return }
        lastError = error.localizedDescription
        stop()
    }

    // MARK: Masques du texte

    private func received(_ id: CGDirectDisplayID, _ found: [Detection], _ seconds: Double) {
        guard isOn, let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return }
        lastOCRSeconds[id] = seconds
        let size = screen.frame.size
        let now = Date()
        var fresh = found.map { d in
            Mask(rect: CGRect(x: d.box.minX * size.width, y: d.box.minY * size.height,
                              width: d.box.width * size.width, height: d.box.height * size.height)
                    .insetBy(dx: -5, dy: -3),
                 label: d.kind.label, style: .text, seen: now)
        }
        // On garde un instant les masques qui ne sont plus vus (évite le clignotement si une lecture rate)
        for old in textMasks[id] ?? [] where now.timeIntervalSince(old.seen) < hold {
            if !fresh.contains(where: { $0.rect.intersects(old.rect) }) { fresh.append(old) }
        }
        textMasks[id] = fresh
        render()
    }

    // MARK: Notifications et apps masquées entièrement

    private func bundleID(_ pid: pid_t) -> String? {
        if let b = bundleCache[pid] { return b }
        let b = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        bundleCache[pid] = b
        return b
    }

    private func scanWindows() {
        guard isOn else { return }
        let wantNotifications = settings.categories.contains(.notifications)
        let fullApps = settings.fullyMaskedBundleIDs
        var masks: [Mask] = []
        var diag: [String] = []
        let now = Date()
        if wantNotifications || !fullApps.isEmpty,
           let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] {
            let me = ProcessInfo.processInfo.processIdentifier
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            var covering: [CGRect] = []
            for w in list {
                guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                      let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                      let cg = CGRect(dictionaryRepresentation: bounds) else { continue }
                let layer = w[kCGWindowLayer as String] as? Int ?? 0
                let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
                guard alpha > 0.01, cg.width > 4, cg.height > 4 else { continue }
                let rect = CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
                let bundle = bundleID(pid) ?? ""

                if bundle == "com.apple.notificationcenterui" {
                    diag.append("layer \(layer) alpha \(alpha) \(Int(cg.minX)),\(Int(cg.minY)) \(Int(cg.width))×\(Int(cg.height)) "
                                + "« \(w[kCGWindowName as String] as? String ?? "") »")
                    if wantNotifications, layer > 0, cg.width <= 760, cg.height <= 900 {
                        masks.append(Mask(rect: rect.insetBy(dx: 6, dy: 6), label: "Notification masquée",
                                          style: .notification, seen: now))
                    }
                    continue
                }
                if layer == 0, fullApps.contains(bundle), cg.width > 60, cg.height > 40 {
                    for piece in subtractRects(rect, covering) where piece.width > 8 && piece.height > 8 {
                        masks.append(Mask(rect: piece, label: "Fenêtre masquée", style: .window, seen: now))
                    }
                }
                if layer >= 0 && layer < 20 { covering.append(rect) }
            }
        }
        diagnosticWindows = diag
        let same = masks.count == windowMasks.count && zip(masks, windowMasks).allSatisfy {
            $0.rect == $1.rect && $0.label == $1.label && $0.style == $1.style
        }
        if !same {
            windowMasks = masks
            render()
        }
    }

    // MARK: Affichage

    private func render() {
        for screen in NSScreen.screens {
            guard let overlay = overlays[screen.displayID] else { continue }
            let f = screen.frame
            var list = textMasks[screen.displayID] ?? []
            for m in windowMasks {
                let i = m.rect.intersection(f)
                guard !i.isNull, i.width > 1, i.height > 1 else { continue }
                var local = m
                local.rect = i.offsetBy(dx: -f.minX, dy: -f.minY)
                list.append(local)
            }
            overlay.view.masks = list
        }
        onChange?()
    }
}
