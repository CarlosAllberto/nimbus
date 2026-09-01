import AppKit
import SwiftUI

/// Liquid Glass on macOS 26+, an `NSVisualEffectView` HUD material
/// everywhere else, and a flat opaque fill when the user has Reduce
/// Transparency on. All three share the same corner radius and hairline
/// border, so only the refraction differs, not the layout.
///
/// The glass branch is additionally gated by `#if compiler(>=6.2)`, not just
/// `#available`: `#available` is a runtime check, but `GlassEffectContainer`
/// and `.glassEffect` are symbols that must resolve at *compile* time. CI
/// builds on a macOS 14 runner whose SDK predates these APIs, so without the
/// compiler gate the build fails there even though the call is behind
/// `#available(macOS 26, *)`.
struct GlassBackground: View {
    var cornerRadius: CGFloat = 20

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                LiquidGlassSurface(cornerRadius: cornerRadius)
            } else {
                VisualEffectSurface(cornerRadius: cornerRadius)
            }
            #else
            VisualEffectSurface(cornerRadius: cornerRadius)
            #endif
        }
    }
}

#if compiler(>=6.2)
@available(macOS 26, *)
private struct LiquidGlassSurface: View {
    let cornerRadius: CGFloat

    /// No `GlassEffectContainer`: that exists to let several glass elements
    /// share one backdrop, and with a single element it renders across the
    /// whole container rect — which showed up as a square behind the rounded
    /// card. The shape passed to `glassEffect` is the silhouette; the clip
    /// keeps anything the effect draws outside it from reaching the shadow.
    var body: some View {
        Color.clear
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
#endif

private struct VisualEffectSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
