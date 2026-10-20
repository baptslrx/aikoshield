import AppKit
import ServiceManagement

struct MaskedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

@MainActor
final class ShieldSettings: ObservableObject {
    static let defaultShortcut = Shortcut(keyCode: 1, carbonModifiers: 6144, label: "⌃ ⌥ S")  // kVK_ANSI_S + ⌃⌥

    /// Gestionnaires de mots de passe : masqués en entier quand « Mots de passe et codes » est actif.
    static let passwordApps: [MaskedApp] = [
        MaskedApp(bundleID: "com.apple.Passwords", name: "Mots de passe"),
        MaskedApp(bundleID: "com.apple.keychainaccess", name: "Trousseau d'accès"),
        MaskedApp(bundleID: "com.1password.1password", name: "1Password"),
        MaskedApp(bundleID: "com.agilebits.onepassword7", name: "1Password 7"),
        MaskedApp(bundleID: "com.bitwarden.desktop", name: "Bitwarden"),
        MaskedApp(bundleID: "com.dashlane.dashlanephonefinal", name: "Dashlane"),
        MaskedApp(bundleID: "com.lastpass.lastpassmacdesktop", name: "LastPass"),
        MaskedApp(bundleID: "in.sinew.Enpass-Desktop", name: "Enpass"),
        MaskedApp(bundleID: "org.keepassxc.keepassxc", name: "KeePassXC"),
        MaskedApp(bundleID: "com.proton.pass.electron", name: "Proton Pass"),
    ]

    private let d = UserDefaults.standard

    @Published var categories: Set<Category> {
        didSet { d.set(categories.map(\.rawValue), forKey: "categories") }
    }
    @Published var maskedApps: [MaskedApp] {
        didSet { if let data = try? JSONEncoder().encode(maskedApps) { d.set(data, forKey: "maskedApps") } }
    }
    @Published var precise: Bool { didSet { d.set(precise, forKey: "precise") } }
    @Published var showLabels: Bool { didSet { d.set(showLabels, forKey: "showLabels") } }
    @Published var startOn: Bool { didSet { d.set(startOn, forKey: "startOn") } }
    @Published var shortcut: Shortcut {
        didSet { if let data = try? JSONEncoder().encode(shortcut) { d.set(data, forKey: "shortcut") } }
    }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    init() {
        if let raw = d.stringArray(forKey: "categories") {
            categories = Set(raw.compactMap(Category.init(rawValue:)))
        } else {
            categories = Set(Category.allCases)
        }
        if let data = d.data(forKey: "maskedApps"), let list = try? JSONDecoder().decode([MaskedApp].self, from: data) {
            maskedApps = list
        } else {
            maskedApps = []
        }
        precise = d.object(forKey: "precise") as? Bool ?? false
        showLabels = d.object(forKey: "showLabels") as? Bool ?? true
        startOn = d.bool(forKey: "startOn")
        if let data = d.data(forKey: "shortcut"), let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = s
        } else {
            shortcut = Self.defaultShortcut
        }
    }

    /// Toutes les apps à cacher entièrement en ce moment.
    var fullyMaskedBundleIDs: Set<String> {
        var ids = Set(maskedApps.map(\.bundleID))
        if categories.contains(.secrets) { ids.formUnion(Self.passwordApps.map(\.bundleID)) }
        return ids
    }

    func toggle(_ c: Category) {
        if categories.contains(c) { categories.remove(c) } else { categories.insert(c) }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
