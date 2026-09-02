import AppKit
import SwiftUI

enum NativeToolKind: String {
    case pickColor = "pick-color"
}

struct NativeToolView: View {
    let kind: NativeToolKind
    let tool: NimbusTool
    let isSidebarVisible: Bool

    var body: some View {
        switch kind {
        case .pickColor:
            PickColorView(tool: tool, isSidebarVisible: isSidebarVisible)
        }
    }
}

private struct PickColorView: View {
    let tool: NimbusTool
    let isSidebarVisible: Bool

    @State private var pickedColor: NSColor?
    @State private var isAuthorized = EyedropperController.isAuthorized()
    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(.title.bold())
                Text(tool.summary)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, isSidebarVisible ? 0 : 52)

            if let pickedColor {
                VStack(alignment: .leading, spacing: 16) {
                    SwatchView(color: Color(nsColor: pickedColor), size: 72)
                    KeyValueTable(rows: rows(for: pickedColor), valuesAreMonospaced: true, showsCopy: true)
                }
            } else {
                Text("Pick a color from anywhere on screen.")
                    .foregroundStyle(.secondary)
            }

            actions
        }
        .frame(maxWidth: 460, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .onAppear {
            // Covers "user granted access in System Settings and came
            // back to Nimbus" — re-checks without requiring a click.
            isAuthorized = EyedropperController.isAuthorized()
        }
        // `onAppear` alone misses the common case: the user never left this
        // tool, they switched to System Settings and came back, so the view
        // never re-appeared. Re-checking on activation catches that.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAuthorized = EyedropperController.isAuthorized()
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isAuthorized {
            VStack(alignment: .leading, spacing: 10) {
                Button(isPicking ? "Picking…" : "Pick a Color (Live)") { startLivePick() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPicking)
                Button("Use System Picker") { startSystemPick() }
                    .buttonStyle(.link)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grant Screen Recording access for a live eyedropper that previews color as you move the cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // macOS hands the permission to a process when it starts, so a
                // grant made while Nimbus is running does not reach it. Saying
                // so here saves the "I already allowed it" dead end.
                Text("Already allowed it? Quit and reopen Nimbus. macOS only applies the permission when the app starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Grant Access") { requestAccess() }
                    Button("Open System Settings") { NSWorkspace.shared.open(EyedropperController.systemSettingsURL) }
                        .buttonStyle(.link)
                }
                Button("Use System Picker") { startSystemPick() }
                    .buttonStyle(.link)
            }
        }
    }

    /// Pick Color does NOT consume quota — it never goes through
    /// FileToolView/FormToolView.runTool(), so it never reaches
    /// UsageQuota.checkAndConsume(). If in the future this tool
    /// should consume quota, add a single call to
    /// UsageQuota.checkAndConsume() here — isolated, 3 lines,
    /// easy to add, not harder by not doing it now.
    private func startLivePick() {
        isPicking = true
        EyedropperController.shared.start(
            onPick: { color in pickedColor = color; isPicking = false },
            onCancel: { isPicking = false }
        )
    }

    /// Fallback with no permission required at all — same body as the
    /// previous round's single button, just renamed.
    private func startSystemPick() {
        NSColorSampler().show { color in
            guard let color else { return }
            MainActor.assumeIsolated { pickedColor = color }
        }
    }

    private func requestAccess() {
        _ = EyedropperController.requestAccess()
        // Can stay false for the already-running process even after
        // granting — see feature-spec 'Nota de ambiente'. Re-checked
        // again in .onAppear if the user leaves and comes back.
        isAuthorized = EyedropperController.isAuthorized()
    }

    private func rows(for color: NSColor) -> [(label: String, value: String)] {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let rgbText = "rgb(\(r), \(g), \(b))"
        let hslText = Self.hslString(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent)
        return [("Hex", hex), ("RGB", rgbText), ("HSL", hslText)]
    }

    private static func hslString(r: CGFloat, g: CGFloat, b: CGFloat) -> String {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        let lightness = (maxV + minV) / 2
        let saturation: CGFloat = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))

        var hue: CGFloat = 0
        if delta != 0 {
            switch maxV {
            case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: hue = (b - r) / delta + 2
            default: hue = (r - g) / delta + 4
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }

        return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }
}