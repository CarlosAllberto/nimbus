import SwiftUI

/// A `TabView` inside macOS's `Settings` scene renders as the native
/// multi-pane preferences window (icon toolbar up top, one pane per tab) —
/// no custom chrome needed to get that look. Each tab is its own view below
/// rather than one long scrolling list, so the window only ever shows one
/// category's worth of controls at a time.
struct PreferencesView: View {
    @Binding var theme: NimbusTheme

    var body: some View {
        TabView {
            GeneralPreferencesTab(theme: $theme)
                .tabItem { Label("General", systemImage: "gearshape") }

            APIKeysPreferencesTab()
                .tabItem { Label("API Keys", systemImage: "key.fill") }

            QuickDropPreferencesTab()
                .tabItem { Label("Quick Drop", systemImage: "tray.and.arrow.down.fill") }
        }
        .frame(width: 420)
    }
}

private struct GeneralPreferencesTab: View {
    @Binding var theme: NimbusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FormRow(label: "Appearance") {
                Picker("Appearance", selection: $theme) {
                    ForEach(NimbusTheme.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160, alignment: .leading)
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .topLeading)
    }
}

private struct APIKeysPreferencesTab: View {
    @State private var geminiAPIKey = ""
    @State private var pageSpeedAPIKey = ""

    private let geminiStore = KeychainSecretStore(account: NimbusSecretAccount.geminiAPIKey)
    private let pageSpeedStore = KeychainSecretStore(account: NimbusSecretAccount.pageSpeedAPIKey)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                FormRow(label: "Gemini API Key") {
                    SecureField("", text: $geminiAPIKey)
                        .formFieldChrome()
                        .accessibilityLabel("Gemini API Key")
                }
                Text("Used by Copy Generator and Contract PDF.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                FormRow(label: "Google PageSpeed API Key") {
                    SecureField("", text: $pageSpeedAPIKey)
                        .formFieldChrome()
                        .accessibilityLabel("Google PageSpeed API Key")
                }
                Text("Used by Site Speed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .topLeading)
        .onAppear {
            geminiAPIKey = (try? geminiStore.read()) ?? ""
            pageSpeedAPIKey = (try? pageSpeedStore.read()) ?? ""
        }
        // No "Done" button in a native prefs pane — fields save as they
        // change instead of on a batched confirm.
        .onChange(of: geminiAPIKey) { _, newValue in save(newValue, to: geminiStore) }
        .onChange(of: pageSpeedAPIKey) { _, newValue in save(newValue, to: pageSpeedStore) }
    }

    /// An emptied field deletes the Keychain item instead of storing "".
    private func save(_ value: String, to store: KeychainSecretStore) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try? trimmed.isEmpty ? store.delete() : store.write(trimmed)
    }
}

private struct QuickDropPreferencesTab: View {
    @AppStorage(QuickDropPreferenceKey.webPOperation) private var webPOperation = "webp"
    @AppStorage(QuickDropPreferenceKey.webPCompression) private var webPCompression = CompressionPreset.glossy.rawValue
    @AppStorage(QuickDropPreferenceKey.webMOperation) private var webMOperation = "webm"
    @AppStorage(QuickDropPreferenceKey.webMCompression) private var webMCompression = CompressionPreset.glossy.rawValue
    @AppStorage(QuickDropPreferenceKey.icoSafeMargin) private var icoSafeMargin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Only affects files dropped on the Quick Drop panel — the tool pages keep their own settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("To WebP")
                    .font(.subheadline.bold())
                FormRow(label: "Operation") {
                    Picker("Operation", selection: $webPOperation) {
                        Text("To WebP").tag("webp")
                        Text("Compress").tag("original")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 175)
                }
                FormRow(label: "Compression") {
                    compressionPicker(selection: $webPCompression)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("To WebM")
                    .font(.subheadline.bold())
                FormRow(label: "Operation") {
                    Picker("Operation", selection: $webMOperation) {
                        Text("To WebM").tag("webm")
                        Text("Compress").tag("original")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 175)
                }
                FormRow(label: "Compression") {
                    compressionPicker(selection: $webMCompression)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Favicon")
                    .font(.subheadline.bold())
                FormRow(label: "Safe Margin") {
                    Picker("Safe Margin", selection: $icoSafeMargin) {
                        Text("Margin Off").tag(false)
                        Text("Margin On").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 175)
                }
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .topLeading)
    }

    /// `@AppStorage` stores `CompressionPreset` by its raw string, so this
    /// binds to that directly rather than the enum `FileToolView`'s own
    /// picker uses — same options and labels either way.
    private func compressionPicker(selection: Binding<String>) -> some View {
        Picker("Compression", selection: selection) {
            ForEach(CompressionPreset.allCases) { preset in
                Text(preset.title).tag(preset.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 200, alignment: .leading)
    }
}
