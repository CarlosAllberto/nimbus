import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FormSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 6)
    }
}

struct FormRow<Content: View>: View {
    let label: String
    var isOptional = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .foregroundStyle(.secondary)
                if isOptional {
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
    }
}

extension View {
    /// Gives a text field the same weight as the multi-line editors: a filled,
    /// bordered box that grows on focus. Applied instead of `.roundedBorder`,
    /// which renders too small and too faint next to the rest of the form.
    func formFieldChrome() -> some View {
        modifier(FormFieldChrome())
    }
}

private struct FormFieldChrome: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(isFocused ? 0.10 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .animation(.snappy(duration: 0.15), value: isFocused)
    }
}

/// Multi-line counterpart to a text field, wearing the same chrome. `TextEditor`
/// paints its own opaque background, so it has to be hidden for the field's fill
/// to show through — otherwise the surrounding padding reads as a thick border.
struct FormTextEditor: View {
    @Binding var text: String
    let label: String
    var placeholder = ""
    var minHeight: CGFloat = 100
    var isMonospaced = false
    /// Lets the editor take whatever height its container offers, for the forms
    /// whose whole body is one editor.
    var fillsHeight = false

    /// Built from the AppKit system font rather than a SwiftUI text style, so the
    /// editor and its placeholder match the text fields — those are NSTextFields
    /// underneath and draw their own prompt in exactly this face and weight.
    private var font: Font {
        Font(
            isMonospaced
                ? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                : NSFont.systemFont(ofSize: NSFont.systemFontSize)
        )
    }

    var body: some View {
        TextEditor(text: $text)
            .font(font)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight, maxHeight: fillsHeight ? .infinity : nil)
            // TextEditor has no prompt of its own, so the placeholder is drawn
            // behind it, inset by the text container's line-fragment padding.
            .overlay(alignment: .topLeading) {
                if text.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .font(font)
                        // The same semantic color AppKit gives a text field's
                        // prompt, so both kinds of field read as one style.
                        .foregroundStyle(Color(nsColor: .placeholderTextColor))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .formFieldChrome()
            .accessibilityLabel(label)
    }
}

struct CompactFileField: View {
    let label: String
    let acceptance: FileAcceptance
    @Binding var url: URL?

    @State private var isDropTargeted = false

    private let thumbnailSize: CGFloat = 40
    private let fieldHeight: CGFloat = 60

    var body: some View {
        Group {
            if let url {
                filledContent(for: url)
            } else {
                emptyContent
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: fieldHeight, maxHeight: fieldHeight, alignment: .leading)
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(url == nil ? 0.55 : 0.25),
                    style: url == nil
                        ? StrokeStyle(lineWidth: 1, dash: [5, 4])
                        : StrokeStyle(lineWidth: 1)
                )
        }
        .dropDestination(for: URL.self) { droppedURLs, _ in
            acceptDrop(droppedURLs)
        } isTargeted: { isDropTargeted = $0 }
        .animation(.snappy, value: isDropTargeted)
    }

    /// `NSOpenPanel` directly rather than SwiftUI's `.fileImporter`: this field
    /// is used inside `FileToolView`, which already carries a `.fileImporter`
    /// for its main drop zone, and a second one nested in the same hierarchy
    /// never presented — clicking the field did nothing while drops still
    /// worked. Forms have no competing importer, which is why the same
    /// component behaved there. Driving the panel directly sidesteps the
    /// conflict wherever the field is used.
    private func chooseFile() {
        // The panel is unusable while the app is in the background — the same
        // reason `QuickDropWell` activates before opening one.
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = acceptance.allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        url = chosen
    }

    private func filledContent(for url: URL) -> some View {
        HStack(spacing: 10) {
            FileThumbnailImage(url: url, size: thumbnailSize, fallbackSymbol: acceptance.symbol)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Button("Replace…") { chooseFile() }
                .buttonStyle(.link)
            Button("Clear") { self.url = nil }
                .buttonStyle(.link)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(url.lastPathComponent)")
    }

    private var emptyContent: some View {
        Button {
            chooseFile()
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .overlay {
                        Image(systemName: acceptance.symbol)
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(isDropTargeted ? "Drop to add \(acceptance.noun)" : "Drop \(acceptance.noun) here")
                    Text("or click to choose")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): no \(acceptance.noun) chosen. Choose a file.")
    }

    private func acceptDrop(_ urls: [URL]) -> Bool {
        guard let acceptedURL = urls.first(where: acceptance.accepts) else { return false }
        url = acceptedURL
        return true
    }
}

struct DynamicList<Item: Identifiable, Row: View>: View {
    let addLabel: String
    @Binding var items: [Item]
    let newItem: () -> Item
    @ViewBuilder var row: (Binding<Item>, Int) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($items) { $item in
                let index = items.firstIndex { $0.id == item.id } ?? 0
                HStack(alignment: .top, spacing: 8) {
                    row($item, index)
                    Button {
                        items.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove item \(index + 1)")
                }
            }
            Button(addLabel) { items.append(newItem()) }
                .buttonStyle(.link)
        }
    }
}

/// Shared NSSavePanel flow — used by the file result branch and by every
/// composer that offers a Save button (code blocks, text tabs, JSON dumps).
@MainActor
func saveToFile(data: Data, suggestedFilename: String, contentType: UTType) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = suggestedFilename
    panel.allowedContentTypes = [contentType]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? data.write(to: url)
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

/// Copies `text` to the pasteboard and flips its own label to "Copied" for a
/// beat. Every composer that shows a copyable value uses this instead of
/// hand-rolling the `didCopy` toggle FormResultView used to own alone.
struct CopyButton: View {
    let text: String
    var label: String = "Copy"
    @State private var didCopy = false
    /// Bumped on every press so `task(id:)` restarts the timer even while the
    /// button is already showing "Copied" — without it the label sticks on the
    /// first press and the button reads as copy-once.
    @State private var presses = 0

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            presses += 1
            withAnimation(.snappy) { didCopy = true }
        } label: {
            // Both labels are laid out, so the button is always as wide as the
            // longer of the two and swapping them resizes nothing. Sizing to
            // whichever string is showing would make the button — and anything
            // sharing its row — jump sideways mid-press.
            ZStack {
                Text(label).hidden()
                Text("Copied").hidden()
                Text(didCopy ? "Copied" : label)
            }
        }
        .task(id: presses) {
            guard presses > 0 else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { didCopy = false }
        }
    }
}

/// One label/value pair. `valueIsMonospaced` is for hashes, versions, raw
/// record data; `showsCopy` adds a trailing `CopyButton` for the value.
struct KeyValueRow: View {
    let label: String
    let value: String
    var valueIsMonospaced = false
    var showsCopy = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(valueIsMonospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsCopy {
                CopyButton(text: value)
            }
        }
    }
}

/// A card of `KeyValueRow`s — WHOIS parsed fields, one DNS provider's
/// records, Site Speed's lab metrics, a Responsive Font Clamp result's meta,
/// Contrast Check's colors, Color Convert's 4 formats.
struct KeyValueTable: View {
    let rows: [(label: String, value: String)]
    var valuesAreMonospaced = false
    var showsCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                KeyValueRow(label: row.label, value: row.value, valueIsMonospaced: valuesAreMonospaced, showsCopy: showsCopy)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum BadgeTone { case pass, fail, neutral, warn }

/// Small pill — WCAG pass/fail, DNS provider status, WordPress CVE counts,
/// Site Speed's strategy tag. `.warn` is the "needs improvement" band
/// (50–89) used by Site Speed scores; only Slice A's site-speed composer
/// reaches it — other tools keep using pass/fail/neutral.
struct BadgeView: View {
    let text: String
    var tone: BadgeTone = .neutral

    private var color: Color {
        switch tone {
        case .pass: .green
        case .fail: .red
        case .warn: .orange
        case .neutral: .secondary
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

/// A solid color chip with an optional caption — Color Convert's preview and
/// Contrast Check's foreground/background chips.
struct SwatchView: View {
    let color: Color
    var caption: String?
    var size: CGFloat = 48

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color)
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25))
                }
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Monospace scrollable text with Copy + Save. No tokenizing syntax
/// highlighter — decision recorded in feature-spec (ask-back, 2026-09-01):
/// color is reserved for badges/status, never for code body text.
struct CodeBlockView: View {
    let code: String
    let suggestedFilename: String
    let contentType: UTType
    var maxHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxHeight: maxHeight)

            HStack(spacing: 12) {
                CopyButton(text: code)
                Button("Save…") { saveToFile(data: Data(code.utf8), suggestedFilename: suggestedFilename, contentType: contentType) }
            }
        }
    }
}

/// One tab of `TabbedTextView` — content plus its own Save target, since
/// "Text"/"HTML"/"React" (Policy Generator) or a page title (Copy Generator)
/// each need a different filename/UTType.
struct FormTextTab {
    let title: String
    let content: String
    let filename: String
    let contentType: UTType
}

/// A segmented picker over named text blocks, each rendered as a
/// `CodeBlockView` — Policy Generator (Text/HTML/React) and Copy Generator
/// (one tab per generated page). The picker hides itself for a single tab.
struct TabbedTextView: View {
    let tabs: [FormTextTab]
    @State private var selection = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tabs.count > 1 {
                Picker("", selection: $selection) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                        Text(tab.title).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if tabs.indices.contains(selection) {
                CodeBlockView(
                    code: tabs[selection].content,
                    suggestedFilename: tabs[selection].filename,
                    contentType: tabs[selection].contentType
                )
            }
        }
    }
}

/// A copyable value with a caption underneath — Password Generator's password
/// and WhatsApp Link's link. The copy button is `.borderedProminent` at the
/// regular control size, matching `FormToolView`'s own action button: on
/// macOS 26 `.controlSize(.large)` turns `.borderedProminent` into a capsule,
/// which is what made the old Copy buttons here look different from the rest
/// of the app.
struct CopyResultCard: View {
    let value: String
    var copyLabel: String = "Copy"
    var caption: String? = nil
    var valueFont: Font = .system(.title3, design: .monospaced)
    /// A link reads better truncated to one line: a wrapped link reads as
    /// broken layout.
    var truncatesMiddle: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value)
                .font(valueFont)
                .textSelection(.enabled)
                .lineLimit(truncatesMiddle ? 1 : nil)
                .truncationMode(truncatesMiddle ? .middle : .tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                if let caption {
                    Text(caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                CopyButton(text: value, label: copyLabel)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A clickable URL plus a copy button. No current caller — WhatsApp Link
/// moved to `CopyResultCard` (feature-spec D7) for the same rounded-corners
/// treatment as the rest of the app's result buttons. Kept rather than
/// deleted per the spec, in case a future tool wants a plain inline link.
struct LinkRow: View {
    let urlString: String

    var body: some View {
        HStack(spacing: 10) {
            if let url = URL(string: urlString) {
                // The label has to be an explicit `Text` for these to apply.
                // Attached to the `Link` itself they used to work, but under
                // the macOS 26 SDK they stop reaching the label it generates
                // from a string, and a long link wraps to a second, indented
                // line instead of truncating — which reads as a broken layout.
                // Middle truncation keeps both the domain and the tail
                // visible; Copy still carries the whole thing.
                Link(destination: url) {
                    Text(urlString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text(urlString)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            CopyButton(text: urlString)
        }
    }
}

/// Pretty-printed JSON with Copy + Save — the whole result view's behavior
/// before this round. Fallback for an unrecognized tool id or a composer
/// whose `JSONDecoder.decode` fails; should never fire on the happy path for
/// any of the 16 catalogued tools.
struct RawJSONFallbackView: View {
    let json: Data

    private var prettyText: String {
        guard
            let object = try? JSONSerialization.jsonObject(with: json),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: pretty, encoding: .utf8)
        else { return "Nimbus returned an invalid response." }
        return text
    }

    var body: some View {
        CodeBlockView(code: prettyText, suggestedFilename: "result.json", contentType: .json, maxHeight: 320)
    }
}
