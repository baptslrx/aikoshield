import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Réglages

struct SettingsView: View {
    @ObservedObject var settings: ShieldSettings
    var onShortcut: () -> Void
    var onChanged: () -> Void
    var onTestPage: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                section("À masquer automatiquement") {
                    ForEach(Category.allCases, id: \.self) { c in
                        Toggle(isOn: Binding(get: { settings.categories.contains(c) },
                                             set: { _ in settings.toggle(c); onChanged() })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(.system(size: 13, weight: .medium))
                                Text(c.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.accentUI)
                    }
                }
                section("Apps cachées en entier") {
                    Text("Leurs fenêtres sont recouvertes pendant le partage. Les gestionnaires de mots de passe "
                         + "le sont déjà quand « Mots de passe et codes » est activé.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if settings.maskedApps.isEmpty {
                        Text("Aucune pour l'instant (idées : Messages, WhatsApp, Mail, ta banque).")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ForEach(settings.maskedApps) { app in
                        HStack {
                            appIcon(app.bundleID)
                            Text(app.name).font(.system(size: 13))
                            Spacer()
                            Button {
                                settings.maskedApps.removeAll { $0 == app }
                                onChanged()
                            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                                .help("Retirer")
                        }
                    }
                    Button("Ajouter une app…") { addApp() }
                }
                section("Détection") {
                    Picker("", selection: Binding(get: { settings.precise },
                                                  set: { settings.precise = $0; onChanged() })) {
                        Text("Rapide (conseillé)").tag(false)
                        Text("Précise (plus lente)").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Toggle("Écrire « masqué » sur les masques",
                           isOn: Binding(get: { settings.showLabels },
                                         set: { settings.showLabels = $0; onChanged() }))
                        .toggleStyle(.switch).tint(Theme.accentUI)
                }
                section("Général") {
                    HStack {
                        Text("Raccourci pour activer / couper")
                        Spacer()
                        Button(settings.shortcut.label) { onShortcut() }
                    }
                    Toggle("Activer le bouclier dès l'ouverture", isOn: $settings.startOn)
                        .toggleStyle(.switch).tint(Theme.accentUI)
                    Toggle("Ouvrir au démarrage du Mac",
                           isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch).tint(Theme.accentUI)
                }
                section("Bon à savoir") {
                    bullet("Partage ton écran entier (Zoom, Meet, Teams, Discord, OBS…) : si tu ne partages qu'une "
                           + "fenêtre, les masques n'apparaissent pas dans le partage.")
                    bullet("Tout se passe sur ton Mac : rien n'est enregistré ni envoyé.")
                    bullet("Une info qui apparaît (ou défile) peut être visible une fraction de seconde avant "
                           + "d'être masquée.")
                    Button("Ouvrir la page de test") { onTestPage() }
                }
            }
            .padding(22)
        }
        .frame(width: 440, height: 640)
        .background(Theme.background(scheme))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.accentText(scheme))
            VStack(alignment: .leading, spacing: 2) {
                Text("AikoShield").font(.system(size: 20, weight: .semibold))
                Text("Partage ton écran sans rien dévoiler").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accentText(scheme))
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface(scheme)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line(scheme)))
        }
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.accentUI).frame(width: 5, height: 5).padding(.top, 6)
            Text(s).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func appIcon(_ bundleID: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let img = url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()
        return Image(nsImage: img).resizable().frame(width: 18, height: 18)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.prompt = "Masquer"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let b = Bundle(url: url), let id = b.bundleIdentifier,
                  !settings.maskedApps.contains(where: { $0.bundleID == id }) else { continue }
            let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            settings.maskedApps.append(MaskedApp(bundleID: id, name: name))
        }
        onChanged()
    }
}

// MARK: - Autorisation « Enregistrement de l'écran »

struct PermissionView: View {
    var onOpenSettings: () -> Void
    var onRelaunch: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accentText(scheme))
                Text("Une autorisation, et c'est prêt").font(.system(size: 18, weight: .semibold))
            }
            Text("Pour repérer les infos sensibles, AikoShield doit voir ton écran. La lecture se fait sur ton Mac : "
                 + "rien n'est enregistré, rien n'est envoyé.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Clique sur « Ouvrir les réglages ».")
                step(2, "Active AikoShield dans « Enregistrement de l'écran et audio du système ».")
                step(3, "Reviens ici et clique sur « Relancer AikoShield ».")
            }
            HStack {
                Button("Ouvrir les réglages") { onOpenSettings() }
                Spacer()
                Button("Relancer AikoShield") { onRelaunch() }
                    .keyboardShortcut(.defaultAction)
                    .tint(Theme.accentUI)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.background(scheme))
    }

    private func step(_ n: Int, _ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.accentUI))
            Text(s).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
