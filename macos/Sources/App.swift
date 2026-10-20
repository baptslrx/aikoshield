import AppKit
import SwiftUI

@main
@MainActor
struct AikoShieldMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var settings: ShieldSettings!
    private var shield: Shield!
    private var statusItem: NSStatusItem!
    private var hotkey: GlobalHotKey!
    private var recorder: ShortcutRecorder!
    private var settingsWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private let toast = Toast()

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = ShieldSettings()
        shield = Shield(settings: settings)
        shield.onChange = { [weak self] in self?.updateIcon() }

        hotkey = GlobalHotKey(signature: OSType(0x414B_5348)) { [weak self] in  // « AKSH »
            MainActor.assumeIsolated { self?.toggleShield() }
        }
        hotkey.register(settings.shortcut)
        recorder = ShortcutRecorder(appName: "AikoShield", purpose: "active ou coupe le bouclier",
                                    fallback: ShieldSettings.defaultShortcut)
        recorder.onSave = { [weak self] s in self?.settings.shortcut = s }
        recorder.onClose = { [weak self] in
            guard let self else { return }
            self.hotkey.register(self.settings.shortcut)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        if !Shield.hasPermission {
            showPermission()
        } else if settings.startOn {
            Task { await shield.start() }
        } else if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            showWelcome()
        }
    }

    // MARK: Bouclier

    private func toggleShield() {
        Task {
            if !shield.isOn && !Shield.hasPermission {
                showPermission()
                return
            }
            await shield.toggle()
            if shield.isOn {
                toast.show("Bouclier activé", icon: "checkmark.shield.fill")
            } else if let err = shield.lastError {
                toast.show("Impossible d'activer le bouclier", icon: "exclamationmark.shield")
                NSLog("AikoShield : %@", err)
            } else {
                toast.show("Bouclier coupé", icon: "shield.slash")
            }
        }
    }

    private func settingsChanged() {
        shield.refreshLabels()
        Task { await shield.restart() }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if shield?.isOn == true {
            let img = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: "AikoShield actif")?
                .withSymbolConfiguration(config.applying(.init(paletteColors: [Theme.accent])))
            img?.isTemplate = false
            button.image = img
            let n = shield.maskedCount
            button.toolTip = "AikoShield — actif" + (n > 0 ? " (\(n) masque\(n > 1 ? "s" : ""))" : "")
        } else {
            let img = NSImage(systemSymbolName: "shield", accessibilityDescription: "AikoShield")?
                .withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
            button.toolTip = "AikoShield — coupé (\(settings?.shortcut.label ?? ""))"
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let on = shield.isOn
        let status = NSMenuItem(title: on ? "Bouclier actif" : "Bouclier coupé", action: nil, keyEquivalent: "")
        status.isEnabled = false
        if on {
            let n = shield.maskedCount
            status.title = n == 0 ? "Bouclier actif · rien à masquer" : "Bouclier actif · \(n) masque\(n > 1 ? "s" : "")"
        }
        menu.addItem(status)
        menu.addItem(item(on ? "Couper le bouclier" : "Activer le bouclier",
                          #selector(menuToggle), detail: settings.shortcut.label))
        menu.addItem(.separator())
        let head = NSMenuItem(title: "Masquer", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        for c in Category.allCases {
            let it = item(c.title, #selector(menuCategory(_:)))
            it.representedObject = c.rawValue
            it.state = settings.categories.contains(c) ? .on : .off
            menu.addItem(it)
        }
        menu.addItem(.separator())
        menu.addItem(item("Ouvrir la page de test", #selector(openTestPage)))
        menu.addItem(item("Réglages…", #selector(openSettings)))
        let help = NSMenuItem(title: "Aide", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(item("Autorisation d'enregistrement de l'écran…", #selector(showPermissionFromMenu)))
        sub.addItem(item("Enregistrer un diagnostic", #selector(saveDiagnostic)))
        help.submenu = sub
        menu.addItem(help)
        menu.addItem(.separator())
        menu.addItem(item("Quitter AikoShield", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector, detail: String? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        if let detail {
            let s = NSMutableAttributedString(string: title)
            s.append(NSAttributedString(string: "    " + detail, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.menuFont(ofSize: 0),
            ]))
            it.attributedTitle = s
        }
        return it
    }

    @objc private func menuToggle() { toggleShield() }

    @objc private func menuCategory(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let c = Category(rawValue: raw) else { return }
        settings.toggle(c)
        settingsChanged()
    }

    @objc private func quit() {
        shield.stop()
        NSApp.terminate(nil)
    }

    // MARK: Fenêtres

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); return }
        let view = SettingsView(settings: settings,
                                onShortcut: { [weak self] in self?.changeShortcut() },
                                onChanged: { [weak self] in self?.settingsChanged() },
                                onTestPage: { [weak self] in self?.openTestPage() })
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Réglages AikoShield"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.center()
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    private func changeShortcut() {
        hotkey.unregister()
        recorder.open(current: settings.shortcut)
    }

    @objc private func showPermissionFromMenu() { showPermission() }

    private func showPermission() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = permissionWindow { w.makeKeyAndOrderFront(nil); return }
        let view = PermissionView(
            onOpenSettings: {
                CGRequestScreenCaptureAccess()  // ajoute AikoShield à la liste des réglages
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            },
            onRelaunch: { Self.relaunch() })
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "AikoShield"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        permissionWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AikoShield est prêt"
        alert.informativeText = """
        Avant de partager ton écran, appuie sur \(settings.shortcut.label) (ou clique sur le bouclier dans la barre des menus). \
        Les e-mails, numéros, IBAN, cartes, codes, mots de passe et notifications sont recouverts automatiquement.

        Ouvre la page de test pour voir le bouclier en action.
        """
        alert.addButton(withTitle: "Ouvrir la page de test")
        alert.addButton(withTitle: "Plus tard")
        if alert.runModal() == .alertFirstButtonReturn { openTestPage() }
    }

    @objc private func openTestPage() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AikoShield-test.html")
        try? TestPage.html.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
        if !shield.isOn { toast.show("Active le bouclier avec \(settings.shortcut.label)", icon: "shield") }
    }

    @objc private func saveDiagnostic() {
        var lines: [String] = []
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        lines.append("AikoShield \(appVersion) — macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
        lines.append("Date : \(Date())")
        lines.append("Autorisation écran : \(Shield.hasPermission ? "oui" : "non")")
        lines.append("Bouclier : \(shield.isOn ? "actif" : "coupé")  — erreur : \(shield.lastError ?? "aucune")")
        lines.append("Catégories : \(settings.categories.map(\.rawValue).sorted().joined(separator: ", "))")
        lines.append("Mode : \(settings.precise ? "précis" : "rapide")  — masques : \(shield.maskedCount)")
        for s in NSScreen.screens {
            let ocr = shield.lastOCRSeconds[s.displayID].map { String(format: "%.0f ms", $0 * 1000) } ?? "—"
            lines.append("Écran \(s.displayID) : \(Int(s.frame.width))×\(Int(s.frame.height)) à \(Int(s.frame.minX)),"
                         + "\(Int(s.frame.minY)) ×\(s.backingScaleFactor)  — lecture : \(ocr)")
        }
        lines.append("Fenêtres du centre de notifications :")
        lines.append(contentsOf: shield.diagnosticWindows.map { "  " + $0 })
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("AikoShield-diagnostic.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Petite bulle « Bouclier activé »

@MainActor
final class Toast {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, icon: String) {
        guard let screen = NSScreen.main else { return }
        let dark = Theme.isDark()
        let ink = dark ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.08, alpha: 1)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = ink
        let image = NSImageView(image: NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)
                .applying(.init(paletteColors: [dark ? Theme.accent : Theme.accentDeep]))) ?? NSImage())
        let stack = NSStackView(views: [image, label])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 18)
        let size = stack.fittingSize

        let p = panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .screenSaver
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.06, green: 0.06, blue: 0.08, alpha: 0.97)
                                          : NSColor(white: 1, alpha: 0.98)).cgColor
        bg.layer?.cornerRadius = size.height / 2
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = Theme.accent.withAlphaComponent(0.6).cgColor
        stack.frame = NSRect(origin: .zero, size: size)
        bg.addSubview(stack)
        p.contentView = bg
        let f = screen.visibleFrame
        p.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - 14,
                          width: size.width, height: size.height), display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    self?.panel?.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated { self?.panel?.orderOut(nil) }
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}
