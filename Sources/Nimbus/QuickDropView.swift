import AppKit
import SwiftUI

enum QuickDropMetrics {
    /// Transparent room around the card, so the entrance scale has somewhere to
    /// grow from without being clipped by the window bounds.
    static let shadowMargin: CGFloat = 24

    /// The gap the *card* should keep from the top of the screen.
    static let screenInsetTop: CGFloat = 2

    static let wellsWidth: CGFloat = 144
    static let expandedWidth: CGFloat = 232

    /// How far the card runs past the right screen edge, so its rounded
    /// right-hand corners are off screen and the panel reads as part of it.
    static let screenBleed: CGFloat = 24
}

/// `@AppStorage` keys for the default choice of each tool that has options,
/// set in `PreferencesView`. They only pre-select a row in the option list
/// (see `NimbusTool.defaultChoiceIndex`); the list always asks.
enum QuickDropPreferenceKey {
    static let webPCompression = "quickDropWebPCompression"
    static let webMCompression = "quickDropWebMCompression"
    static let convertFormat = "quickDropConvertFormat"
    static let videoConvertFormat = "quickDropVideoConvertFormat"
    static let icoSafeMargin = "quickDropIcoSafeMargin"
}

/// What each well accepts. Everything is an image except the two video tools;
/// Favicon Generator takes a single file.
func quickDropAcceptance(for tool: NimbusTool) -> FileAcceptance {
    ["to-webm", "video-convert"].contains(tool.id) ? .video : .image
}

private func quickDropAllowsMultipleFiles(for tool: NimbusTool) -> Bool {
    tool.id != "ico"
}

/// One dropped file's place in the run currently showing.
private struct QuickDropRunItem: Identifiable, Equatable {
    let url: URL
    var status: QuickDropRunStatus
    var id: URL { url }
}

/// File sizes in bytes before and after a compression.
private struct QuickDropSizes: Equatable {
    let before: Int
    let after: Int

    /// Whole percent saved; negative when the output grew.
    var savedPercent: Int { before > 0 ? Int((Double(before - after) / Double(before) * 100).rounded()) : 0 }
}

private enum QuickDropRunStatus: Equatable {
    case processing
    case done(QuickDropSizes?)
    case failed(String)
}

/// Files that were dropped and are waiting for the user to pick an option.
/// Tools with no options never get here (see `QuickDropSession.offer`).
struct QuickDropPending {
    let tool: NimbusTool
    let files: [URL]
    let choices: [ToolChoice]
    var selection: Int
}

/// A drop that's in flight: which tool it's running, and each file's own
/// progress. Held by `QuickDropView` itself now, not by the individual well
/// that started it — the whole panel switches to showing this, not just the
/// one well, so ownership has to live above all the wells.
private struct QuickDropRun {
    let tool: NimbusTool
    let acceptance: FileAcceptance
    var items: [QuickDropRunItem]
}

/// The Quick Drop targets, one per `ToolCatalog` entry.
/// Dropping onto one replaces the whole grid with a `QuickDropRunList`
/// showing that drop's progress — see `startRun`.
struct QuickDropView: View {
    @ObservedObject var session: QuickDropSession
    let onDismiss: () -> Void

    @State private var hasAppeared = false
    @State private var run: QuickDropRun?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let runner: any ToolRunner = EngineToolRunner()

    private static let columns = [GridItem(.flexible())]

    private func well(for tool: NimbusTool) -> some View {
        QuickDropWell(
            tool: tool,
            acceptance: quickDropAcceptance(for: tool),
            allowsMultipleFiles: quickDropAllowsMultipleFiles(for: tool),
            onDrop: { files in session.offer(tool: tool, files: files) }
        )
    }

    var body: some View {
        Group {
            if let run {
                QuickDropRunList(tool: run.tool, acceptance: run.acceptance, items: run.items)
                    .transition(.opacity)
            } else if let pending = session.pending {
                QuickDropOptionList(pending: pending) { index in
                    session.pending?.selection = index
                    session.confirm()
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: Self.columns, spacing: 12) {
                        ForEach(ToolCatalog.tools) { well(for: $0) }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(18)
        // Narrow for the wells, wider for the option and run lists, which need
        // room for their text.
        .frame(width: run == nil && session.pending == nil ? QuickDropMetrics.wellsWidth : QuickDropMetrics.expandedWidth)
        .padding(.trailing, QuickDropMetrics.screenBleed)
        .background(GlassBackground(cornerRadius: 20, style: .prominent))
        // Flattens the card into one rounded layer, so nothing the glass draws
        // reaches past the card's silhouette — including into the window shadow
        // AppKit derives from it.
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .compositingGroup()
        // No SwiftUI `.shadow` here: it cannot derive a silhouette from the
        // glass backdrop and falls back to the bounding box, which paints a
        // square halo (clipping and compositing the card first does not fix
        // it). The window draws the shadow instead — AppKit computes it from
        // the alpha actually rendered, so it follows the rounded card.
        .opacity(reduceMotion && !hasAppeared ? 0 : 1)
        .padding(QuickDropMetrics.shadowMargin)
        .animation(.snappy, value: run == nil)
        .animation(.snappy, value: session.pending == nil)
        // The window is sized for the tallest state and sits centred on the
        // screen, so centring the card in it keeps every state centred.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .onAppear {
            session.onConfirm = { startRun($0) }
            session.flush()
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.12)) { hasAppeared = true }
            } else {
                withAnimation(.easeOut(duration: 0.25)) { hasAppeared = true }
            }
        }
        .onExitCommand {
            if session.pending != nil { session.pending = nil } else { onDismiss() }
        }
        .environmentObject(session)
    }

    /// The whole grid disappears the moment a drop is confirmed — only one
    /// drop happens at a time, so there is nothing left for the other wells to do until this one settles and the panel closes.
    @MainActor
    private func startRun(_ pending: QuickDropPending) {
        guard run == nil else { return }
        session.pending = nil
        let acceptance = quickDropAcceptance(for: pending.tool)
        run = QuickDropRun(tool: pending.tool, acceptance: acceptance, items: pending.files.map { QuickDropRunItem(url: $0, status: .processing) })
        Task { await process(pending, acceptance: acceptance) }
    }

    /// Sequential rather than concurrent: compression can be several full
    /// encodes per file. Every file's row updates as its own run settles,
    /// rather than the whole run waiting to report anything.
    @MainActor
    private func process(_ pending: QuickDropPending, acceptance: FileAcceptance) async {
        let option = pending.choices.isEmpty ? nil : pending.choices[pending.selection].option
        let sourceURLs = run?.items.map(\.url) ?? []

        for (index, sourceURL) in sourceURLs.enumerated() {
            do {
                let size = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= acceptance.maximumBytes else {
                    throw QuickDropError.tooLarge(acceptance.maximumSizeMessage)
                }
                let outputURL = try await runner.run(tool: pending.tool, file: sourceURL, option: option)
                // Only the compress tools report savings; the others change format or shape.
                let sizes = ["to-webp", "to-webm"].contains(pending.tool.id) ? Self.sizes(from: sourceURL, to: outputURL) : nil
                withAnimation(.snappy) { run?.items[index].status = .done(sizes) }
            } catch {
                withAnimation(.snappy) { run?.items[index].status = .failed(error.localizedDescription) }
            }
        }

        // Held on screen deliberately: long enough for someone glancing over
        // to read every row's outcome, not just catch a flash of green.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        onDismiss()
    }
}

extension QuickDropView {
    fileprivate static func sizes(from source: URL, to output: URL) -> QuickDropSizes? {
        guard
            let before = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            let after = try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else { return nil }
        return QuickDropSizes(before: before, after: after)
    }
}

private enum QuickDropError: LocalizedError {
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case let .tooLarge(message): message
        }
    }
}

/// Replaces the grid after a drop on a tool with options: one row per choice,
/// the Preferences default pre-selected. Up/Down/Return/Esc are handled at the
/// panel (`QuickDropSession.handleKey`); clicking a row works too.
private struct QuickDropOptionList: View {
    let pending: QuickDropPending
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pending.tool.name)
                    .font(.headline)
                Text(pending.files.count == 1 ? pending.files[0].lastPathComponent : String(localized: "\(pending.files.count) files", bundle: .l10n))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(spacing: 8) {
                ForEach(Array(pending.choices.enumerated()), id: \.element.id) { index, choice in
                    let isSelected = index == pending.selection
                    Button { onChoose(index) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.title).font(.callout)
                                if let detail = choice.detail {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "return").foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.accentColor.opacity(0.30) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Text("↑↓ choose · Return run · Esc cancel", bundle: .l10n)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Replaces the grid for the duration of one drop: the tool's name, then
/// every dropped file's own row, each carrying its own status.
private struct QuickDropRunList: View {
    let tool: NimbusTool
    let acceptance: FileAcceptance
    let items: [QuickDropRunItem]

    @State private var rowsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tool.name)
                .font(.headline)

            // A bare `ScrollView` always takes the full 280pt, so the height
            // follows the rows until they outgrow it.
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        QuickDropRunRow(item: item, fallbackSymbol: acceptance.symbol)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
            }
            .frame(height: min(rowsHeight, 280))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuickDropRunRow: View {
    let item: QuickDropRunItem
    let fallbackSymbol: String

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnailImage(url: item.url, size: 44, fallbackSymbol: fallbackSymbol)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { statusBadge }
                .saturation(isDone ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case let .done(sizes?) = item.status {
                    Text("\(Self.bytes(sizes.before)) → \(Self.bytes(sizes.after))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(sizes.savedPercent >= 0 ? String(localized: "\(sizes.savedPercent)% smaller", bundle: .l10n) : String(localized: "\(-sizes.savedPercent)% larger", bundle: .l10n))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(sizes.savedPercent >= 0 ? Color.green : .orange)
                        .lineLimit(1)
                } else {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.url.lastPathComponent)
        .accessibilityValue(statusText)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .processing:
            ZStack {
                Color.black.opacity(0.35)
                ProgressView().controlSize(.small)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .done:
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 15))
                    .padding(2)
            }
        case .failed:
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                Image(systemName: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .font(.system(size: 15))
                    .padding(2)
            }
        }
    }

    private var isDone: Bool {
        if case .done = item.status { return true }
        return false
    }

    private static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private var statusText: String {
        switch item.status {
        case .processing: String(localized: "Processing…", bundle: .l10n)
        case .done: String(localized: "Done", bundle: .l10n)
        case let .failed(message): message
        }
    }

    private var statusColor: Color {
        if case .failed = item.status { return .orange }
        return .secondary
    }
}

/// A drop target: a big square that is a comfortable target during a drag.
/// Purely a picker now — accepting files reports them to `QuickDropView`
/// via `onDrop` rather than processing them itself, since a drop replaces
/// the whole grid (this well included) with the run list above.
private struct QuickDropWell: View {
    let tool: NimbusTool
    let acceptance: FileAcceptance
    let allowsMultipleFiles: Bool
    let onDrop: ([URL]) -> Void

    @EnvironmentObject private var session: QuickDropSession

    @State private var isDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        Button {
            chooseFiles()
        } label: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        // 0.08 and a 1pt dashed border while targeted.
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(isHovered ? 0.20 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.8 : 0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        }
        .dropDestination(for: URL.self) { droppedURLs, _ in
            acceptFiles(droppedURLs)
        } isTargeted: { isDropTargeted = $0 }
        .onHover { isHovered = $0 }
        .animation(.snappy, value: isDropTargeted)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(String(localized: "\(tool.name), accepts \(acceptance.noun) files", bundle: .l10n))
        .accessibilityValue(String(localized: "Drop \(acceptance.noun) file here", bundle: .l10n))
        .help(tool.summary)
    }

    private var content: some View {
        VStack(spacing: 8) {
            Image(systemName: tool.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            // Every tool name is two words: one per line, so all labels are two lines tall.
            Text(tool.name.replacingOccurrences(of: " ", with: "\n"))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(.horizontal, 10)
    }

    /// A free-standing `NSOpenPanel`, not `.fileImporter`: that attaches a sheet
    /// to this narrow panel, which stretched it and pushed it off to the left.
    /// `NSOpenPanel` is unusable while the app is in the background, and the
    /// panel deliberately opens without activating Nimbus — so the app is
    /// activated here, at the one moment that needs it. `importerDepth` keeps
    /// the popup from closing under the dialog.
    private func chooseFiles() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = acceptance.allowedContentTypes
        openPanel.allowsMultipleSelection = allowsMultipleFiles
        openPanel.level = .modalPanel
        NSApp.activate()
        session.importerDepth += 1
        openPanel.begin { response in
            session.importerDepth -= 1
            if response == .OK { acceptFiles(openPanel.urls) }
        }
    }

    @discardableResult
    private func acceptFiles(_ droppedURLs: [URL]) -> Bool {
        let acceptedFiles = droppedURLs.filter(acceptance.accepts)
        let filesToProcess = allowsMultipleFiles ? acceptedFiles : Array(acceptedFiles.prefix(1))
        guard !filesToProcess.isEmpty else { return false }
        onDrop(filesToProcess)
        return true
    }
}
