import SwiftUI
import ServiceManagement

/// A segmented picker over the two panes. (A `TabView` in a plain `NSWindow`
/// draws its tab strip as a stray bar across the top.)
struct PreferencesView: View {
    private enum Pane { case general, quickDrop }
    @State private var pane = Pane.general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                Text("General", bundle: .l10n).tag(Pane.general)
                Text("Quick Drop", bundle: .l10n).tag(Pane.quickDrop)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 200)
            .padding(.top, 20)

            switch pane {
            case .general: GeneralPreferencesTab()
            case .quickDrop: QuickDropPreferencesTab()
            }
        }
        .frame(width: 420)
    }
}

private struct GeneralPreferencesTab: View {
    @ObservedObject private var updateIndicator = UpdateIndicator.shared
    // Mirrors `SMAppService.mainApp.status` in local state so the Toggle has
    // something to bind to; re-read on appear since the user can also flip
    // this from System Settings > General > Login Items directly.
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginItemStatus = LaunchAtLogin.status
    @AppStorage("nimbusLanguage") private var language = "system"
    @State private var languageChanged = false
    @AppStorage(QuickDropPreferenceKey.edge) private var edge = QuickDropEdge.right.rawValue

    /// Starts a second instance of this app, then quits this one.
    private static func relaunch() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } else if let executable = Bundle.main.executableURL {
            // `swift build` binary: no bundle to reopen.
            try? Process.run(executable, arguments: [])
            NSApp.terminate(nil)
        }
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(String(localized: "Launch Nimbus at Login", bundle: .l10n), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.setEnabled(newValue)
                        loginItemStatus = LaunchAtLogin.status
                    }
                if loginItemStatus == .requiresApproval {
                    HStack(spacing: 6) {
                        Text("macOS needs you to approve this in Login Items.", bundle: .l10n)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Open Settings", bundle: .l10n)) { NSWorkspace.shared.open(LaunchAtLogin.loginItemsSettingsURL) }
                            .buttonStyle(.link)
                    }
                }
            }
            .onAppear {
                launchAtLogin = LaunchAtLogin.isEnabled
                loginItemStatus = LaunchAtLogin.status
            }

            // The shortcut is a fixed constant (see `QuickDropShortcut`), so
            // it is shown, not edited.
            LabeledContent(String(localized: "Quick Drop Shortcut", bundle: .l10n)) {
                Text("⌥⇧Q")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }

            LabeledContent(String(localized: "Popup position", bundle: .l10n)) {
                Picker("", selection: $edge) {
                    Text("Top", bundle: .l10n).tag(QuickDropEdge.top.rawValue)
                    Text("Left", bundle: .l10n).tag(QuickDropEdge.left.rawValue)
                    Text("Bottom", bundle: .l10n).tag(QuickDropEdge.bottom.rawValue)
                    Text("Right", bundle: .l10n).tag(QuickDropEdge.right.rawValue)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            // `AppleLanguages` in the app's own defaults is what both the
            // system and `Bundle.l10n` read, so it takes effect on next launch.
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(String(localized: "Language", bundle: .l10n)) {
                    Picker("", selection: $language) {
                        Text("System default", bundle: .l10n).tag("system")
                        Text(verbatim: "English").tag("en")
                        Text(verbatim: "Português").tag("pt-BR")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                .onChange(of: language) { _, newValue in
                    if newValue == "system" {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    }
                    languageChanged = true
                }
                if languageChanged {
                    HStack(spacing: 6) {
                        Text("Restart Nimbus to apply the new language.", bundle: .l10n)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Restart", bundle: .l10n), action: Self.relaunch)
                            .buttonStyle(.link)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Version \(currentVersion) (build \(currentBuild))", bundle: .l10n)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let info = updateIndicator.available {
                    HStack(spacing: 10) {
                        Text("A newer version (\(info.versionString)) is available.", bundle: .l10n)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Install", bundle: .l10n)) { AppUpdater.shared.checkForUpdates() }
                            .buttonStyle(.link)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .topLeading)
    }
}

private struct QuickDropPreferencesTab: View {
    @AppStorage(QuickDropPreferenceKey.webPCompression) private var webPCompression = CompressionLevel.low.rawValue
    @AppStorage(QuickDropPreferenceKey.webMCompression) private var webMCompression = CompressionLevel.low.rawValue
    @AppStorage(QuickDropPreferenceKey.convertFormat) private var convertFormat = ImageConverter.Format.png.rawValue
    @AppStorage(QuickDropPreferenceKey.videoConvertFormat) private var videoConvertFormat = VideoConverter.Format.mp4.rawValue
    @AppStorage(QuickDropPreferenceKey.icoSafeMargin) private var icoSafeMargin = false

    var body: some View {
        // `.columns` lines every label and menu up in two shared columns.
        Form {
            Text("What is pre-selected when you drop files on the Quick Drop panel.", bundle: .l10n)
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent(String(localized: "Compress Images", bundle: .l10n)) {
                compressionPicker(selection: $webPCompression)
            }
            LabeledContent(String(localized: "Compress Videos", bundle: .l10n)) {
                compressionPicker(selection: $webMCompression)
            }
            LabeledContent(String(localized: "Image Converter", bundle: .l10n)) {
                Picker(String(localized: "Format", bundle: .l10n), selection: $convertFormat) {
                    ForEach(ImageConverter.Format.allCases, id: \.rawValue) { format in
                        Text(format.rawValue.uppercased()).tag(format.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200, alignment: .leading)
            }
            LabeledContent(String(localized: "Video Converter", bundle: .l10n)) {
                Picker(String(localized: "Format", bundle: .l10n), selection: $videoConvertFormat) {
                    ForEach(VideoConverter.Format.allCases, id: \.rawValue) { format in
                        Text(format.rawValue.uppercased()).tag(format.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200, alignment: .leading)
            }
            LabeledContent(String(localized: "Favicon Generator", bundle: .l10n)) {
                Picker(String(localized: "Margin", bundle: .l10n), selection: $icoSafeMargin) {
                    Text("No margin", bundle: .l10n).tag(false)
                    Text("Safe margin", bundle: .l10n).tag(true)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200, alignment: .leading)
            }
        }
        .formStyle(.columns)
        .padding(24)
        .frame(width: 420, alignment: .topLeading)
    }

    /// `@AppStorage` stores `CompressionLevel` by its raw string, so this
    /// binds to that directly.
    private func compressionPicker(selection: Binding<String>) -> some View {
        Picker(String(localized: "Compression", bundle: .l10n), selection: selection) {
            ForEach(CompressionLevel.allCases) { level in
                Text(level.title).tag(level.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 200, alignment: .leading)
    }
}
