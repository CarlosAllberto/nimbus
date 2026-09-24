import SwiftUI
import UniformTypeIdentifiers

/// Composes the per-tool result panel for every form tool whose
/// `FormToolKind` belongs to slice B (`.sliceB`): `copy-generator`,
/// `json-creator`, `responsive-font-clamp`, `html-minify`, `js-minify`,
/// `password-generator`, `color-convert`, `contrast-check`, `wa-link`.
struct FormResultSliceB: View {
    let kind: FormToolKind
    let json: Data

    var body: some View {
        switch kind {
        case .copyGenerator:
            decoded(CopyGeneratorResult.self) { result in
                copyGeneratorView(result)
            }
        case .jsonCreator:
            jsonCreatorView()
        case .responsiveFontClamp:
            decoded(ResponsiveFontClampResult.self) { result in
                responsiveFontClampView(result)
            }
        case .htmlMinify:
            decoded(HtmlMinifyResult.self) { result in
                CodeBlockView(code: result.result, suggestedFilename: "result.html", contentType: .html, maxHeight: .infinity)
            }
        case .jsMinify:
            decoded(JsMinifyResult.self) { result in
                CodeBlockView(code: result.result, suggestedFilename: "result.js", contentType: UTType(filenameExtension: "js") ?? .plainText, maxHeight: .infinity)
            }
        case .passwordGenerator:
            decoded(PasswordGeneratorResult.self) { result in
                passwordGeneratorView(result)
            }
        case .colorConvert:
            decoded(ColorConvertResult.self) { result in
                colorConvertView(result)
            }
        case .contrastCheck:
            decoded(ContrastCheckResult.self) { result in
                contrastCheckView(result)
            }
        case .waLink:
            decoded(WaLinkResult.self) { result in
                CopyResultCard(
                    value: result.link,
                    caption: "Opens a WhatsApp chat",
                    valueFont: .body,
                    truncatesMiddle: true
                )
            }
        // Slice A cases never reach here — `FormResultView` routes them to
        // `FormResultSliceA` first. Kept as defensive fallback only; the
        // raw panel shows what happened if routing ever drifts.
        default: RawJSONFallbackView(json: json)
        }
    }

    @ViewBuilder
    private func copyGeneratorView(_ result: CopyGeneratorResult) -> some View {
        if result.pages.isEmpty {
            Text("No pages were generated.")
                .foregroundStyle(.secondary)
        } else {
            TabbedTextView(tabs: result.pages.enumerated().map { index, page in
                FormTextTab(
                    title: page.title,
                    content: page.content,
                    filename: "\(Self.slugify(page.title, fallback: "page-\(index + 1)")).txt",
                    contentType: .plainText
                )
            })
        }
    }

    @ViewBuilder
    private func jsonCreatorView() -> some View {
        if
            let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
            let inner = object["json"],
            let prettyData = try? JSONSerialization.data(withJSONObject: inner, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: prettyData, encoding: .utf8)
        {
            CodeBlockView(code: text, suggestedFilename: "result.json", contentType: .json)
        } else {
            RawJSONFallbackView(json: json)
        }
    }

    @ViewBuilder
    private func responsiveFontClampView(_ result: ResponsiveFontClampResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(result.results.enumerated()), id: \.offset) { _, r in
                CopyResultCard(value: r.clampValue, valueFont: .system(.body, design: .monospaced))
            }
        }
    }

    @ViewBuilder
    private func passwordGeneratorView(_ result: PasswordGeneratorResult) -> some View {
        CopyResultCard(
            value: result.password,
            copyLabel: "Copy Password",
            caption: "\(result.password.count) characters"
        )
    }

    @ViewBuilder
    private func colorConvertView(_ result: ColorConvertResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SwatchView(color: colorFromHex(result.hex) ?? .gray, size: 56)
                Text(result.original).foregroundStyle(.secondary)
            }
            KeyValueTable(
                rows: [
                    ("Hex", result.hex),
                    ("RGB", result.rgb),
                    ("RGBA", result.rgba),
                    ("HSL", result.hsl),
                ],
                valuesAreMonospaced: true,
                showsCopy: true
            )
        }
    }

    @ViewBuilder
    private func contrastCheckView(_ result: ContrastCheckResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SwatchView(color: colorFromHex(result.foreground.hex) ?? .primary, caption: "Text", size: 44)
                SwatchView(color: colorFromHex(result.background.hex) ?? .white, caption: "Background", size: 44)
                Text("Aa")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(colorFromHex(result.foreground.hex) ?? .primary)
                    .frame(width: 64, height: 64)
                    .background(colorFromHex(result.background.hex) ?? .white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer(minLength: 0)
                VStack(alignment: .trailing) {
                    Text(String(format: "%.2f", result.ratio)).font(.title2.bold())
                    Text("contrast ratio").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                BadgeView(text: "AA Normal \(result.wcag.aaNormal ? "Pass" : "Fail")", tone: result.wcag.aaNormal ? .pass : .fail)
                BadgeView(text: "AA Large \(result.wcag.aaLarge ? "Pass" : "Fail")", tone: result.wcag.aaLarge ? .pass : .fail)
                BadgeView(text: "AAA Normal \(result.wcag.aaaNormal ? "Pass" : "Fail")", tone: result.wcag.aaaNormal ? .pass : .fail)
                BadgeView(text: "AAA Large \(result.wcag.aaaLarge ? "Pass" : "Fail")", tone: result.wcag.aaaLarge ? .pass : .fail)
            }
        }
    }

    /// Lowercase, replace non-alphanumeric with `-`, collapse repeats, trim.
    /// Falls back to `fallback` when the result is empty (e.g. a page titled
    /// only with punctuation). Local to this file: only copy-generator uses it.
    static func slugify(_ raw: String, fallback: String) -> String {
        var s = raw.lowercased()
        var collapsed = ""
        var lastWasDash = false
        for scalar in s.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                collapsed.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                collapsed.append("-")
                lastWasDash = true
            }
        }
        s = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? fallback : s
    }

    /// Decode helper that every composer ends up wanting: try the JSON
    /// `Decoder` against the typed shape, fall back to the raw panel on
    /// failure so a single bad field doesn't kill the whole composer.
    @ViewBuilder
    func decoded<T: Decodable, V: View>(_ type: T.Type, @ViewBuilder content: (T) -> V) -> some View {
        if let value = try? JSONDecoder().decode(T.self, from: json) {
            content(value)
        } else {
            RawJSONFallbackView(json: json)
        }
    }
}

// MARK: - Decoded shapes

struct CopyGeneratorResult: Decodable {
    let pages: [CopyPage]
}

struct CopyPage: Decodable {
    let title: String
    let content: String
}

struct ResponsiveFontClampResult: Decodable {
    let results: [ClampResult]
}

struct ClampResult: Decodable {
    let clampValue: String
}

struct HtmlMinifyResult: Decodable {
    let result: String
}

struct JsMinifyResult: Decodable {
    let result: String
}

struct PasswordGeneratorResult: Decodable {
    let password: String
}

struct ColorConvertResult: Decodable {
    let original: String
    let hex: String
    let rgb: String
    let rgba: String
    let hsl: String
}

struct ContrastCheckResult: Decodable {
    let foreground: ContrastColorInfo
    let background: ContrastColorInfo
    let ratio: Double
    let wcag: WcagInfo
}

struct ContrastColorInfo: Decodable {
    let hex: String
    let rgb: String
}

struct WcagInfo: Decodable {
    let aaNormal: Bool
    let aaLarge: Bool
    let aaaNormal: Bool
    let aaaLarge: Bool
}

struct WaLinkResult: Decodable {
    let link: String
}

// MARK: - Color hex parsing

/// Parses `#rrggbb` or `#rrggbbaa` (always with `#`, lowercase, never the
/// 3-digit shorthand — that's what `tinycolor.toHexString()` /
/// `toHex8String()` produces). Used by `color-convert` (preview swatch) and
/// `contrast-check` (foreground/background + "Aa" sample).
///
/// Local to this file on purpose: `FileToolView.swift:755` already defines
/// `Color(hex:)` for slice A, but it only accepts 6-digit hex — `tinycolor`
/// emits the 8-digit form whenever alpha != 1 (e.g. `color-convert.mjs:28`,
/// `contrast-check.mjs:61/65`), so re-using slice A's helper here would
/// silently fall through to the gray/white default for any color with
/// alpha, dropping R/G/B along with A. Same boundary rule as the rest of
/// the slice: don't touch another slice's files.
private func colorFromHex(_ hex: String) -> Color? {
    var s = hex
    guard s.hasPrefix("#") else { return nil }
    s.removeFirst()
    guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
    let r: Double
    let g: Double
    let b: Double
    let a: Double
    if s.count == 8 {
        r = Double((value >> 24) & 0xFF) / 255
        g = Double((value >> 16) & 0xFF) / 255
        b = Double((value >> 8) & 0xFF) / 255
        a = Double(value & 0xFF) / 255
    } else {
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
        a = 1
    }
    return Color(red: r, green: g, blue: b, opacity: a)
}