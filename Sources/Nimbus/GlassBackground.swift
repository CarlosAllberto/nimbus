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
/// How dark the glass renders. `.standard` is the current look everywhere;
/// `.prominent` is a deeper, more opaque pane — the Spotlight search card and
/// Quick Drop card sit over busy content (a web page, another app's window),
/// and a faint pane there reads as "floating widget" instead of "search box".
/// The default preserves every existing call site, which all want `.standard`.
enum GlassBackgroundStyle {
    case standard
    case prominent
}

struct GlassBackground: View {
    var cornerRadius: CGFloat = 20
    var style: GlassBackgroundStyle = .standard

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
                LiquidGlassSurface(cornerRadius: cornerRadius, style: style)
            } else {
                VisualEffectSurface(cornerRadius: cornerRadius, style: style)
            }
            #else
            VisualEffectSurface(cornerRadius: cornerRadius, style: style)
            #endif
        }
    }
}

#if compiler(>=6.2)
@available(macOS 26, *)
private struct LiquidGlassSurface: View {
    let cornerRadius: CGFloat
    let style: GlassBackgroundStyle

    /// `.prominent` tints the pane toward black so it reads as a deeper,
    /// more insulating surface. The tint is a fraction of the pane's own
    /// refraction — it darkens without painting a flat color over it.
    private var tint: Color {
        switch style {
        case .standard: return .clear
        case .prominent: return Color.black.opacity(0.34)
        }
    }

    /// No `GlassEffectContainer`: that exists to let several glass elements
    /// share one backdrop, and with a single element it renders across the
    /// whole container rect — which showed up as a square behind the rounded
    /// card. The shape passed to `glassEffect` is the silhouette; the clip
    /// keeps anything the effect draws outside it from reaching the shadow.
    var body: some View {
        Color.clear
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
#endif

private struct VisualEffectSurface: View {
    let cornerRadius: CGFloat
    let style: GlassBackgroundStyle

    /// `.prominent` uses a darker material plus a low-opacity black backing so
    /// the pane reads as a deeper surface on the pre-Liquid-Glass path too —
    /// the same visual difference, not two different effects.
    private var material: NSVisualEffectView.Material {
        switch style {
        case .standard: return .hudWindow
        case .prominent: return .headerView
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: material, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            if style == .prominent {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
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
