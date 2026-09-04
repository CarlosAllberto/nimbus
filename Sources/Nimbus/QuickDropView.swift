import AppKit
import SwiftUI

enum QuickDropMetrics {
    /// Transparent room around the card, so the entrance scale has somewhere to
    /// grow from without being clipped by the window bounds.
    static let shadowMargin: CGFloat = 24

    /// The gap the *card* should keep from the top of the screen.
    static let screenInsetTop: CGFloat = 2

    /// The gap the *card* should keep from the right edge — wider than the
    /// top gap on purpose, so the panel doesn't sit flush in the corner.
    static let screenInsetTrailing: CGFloat = 24
}

/// `@AppStorage` keys for Quick Drop's own tool options, set in
/// `PreferencesView` and read only by `QuickDropView` below. Deliberately
/// separate from `FileToolView`'s per-session `@State` (that view resets to
/// its own glossy/convert-on/margin-off defaults every time it appears) —
/// Quick Drop has no options UI of its own, so these are the only place its
/// behavior can be configured, and they never touch the main tool pages.
enum QuickDropPreferenceKey {
    static let webPOperation = "quickDropWebPOperation"
    static let webPCompression = "quickDropWebPCompression"
    static let webMOperation = "quickDropWebMOperation"
    static let webMCompression = "quickDropWebMCompression"
    static let icoSafeMargin = "quickDropICOSafeMargin"
}

/// One dropped file's place in the run currently showing.
private struct QuickDropRunItem: Identifiable, Equatable {
    let url: URL
    var status: QuickDropRunStatus
    var id: URL { url }
}

private enum QuickDropRunStatus: Equatable {
    case processing
    case done
    case failed(String)
}

/// A drop that's in flight: which tool it's running, and each file's own
/// progress. Held by `QuickDropView` itself now, not by the individual well
/// that started it — the whole panel switches to showing this, not just the
/// one well, so ownership has to live above all four wells.
private struct QuickDropRun {
    let tool: NimbusTool
    let acceptance: FileAcceptance
    var items: [QuickDropRunItem]
}

/// The four Quick Drop targets, read from `ToolCatalog`/`FileToolConfiguration`
/// so name, icon and accepted types never drift from the tools they mirror.
/// Dropping onto one replaces the whole grid with a `QuickDropRunList`
/// showing that drop's progress — see `startRun`.
struct QuickDropView: View {
    let session: QuickDropSession
    let onDismiss: () -> Void

    @State private var hasAppeared = false
    @State private var run: QuickDropRun?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Only the ones matching the dropped tool's id are ever read (see
    // `requestFields`); declaring all 5 unconditionally is what
    // `@AppStorage` requires.
    @AppStorage(QuickDropPreferenceKey.webPOperation) private var webPOperation = "webp"
    @AppStorage(QuickDropPreferenceKey.webPCompression) private var webPCompression = CompressionPreset.glossy.rawValue
    @AppStorage(QuickDropPreferenceKey.webMOperation) private var webMOperation = "webm"
    @AppStorage(QuickDropPreferenceKey.webMCompression) private var webMCompression = CompressionPreset.glossy.rawValue
    @AppStorage(QuickDropPreferenceKey.icoSafeMargin) private var icoSafeMargin = false

    private static let toolIDs = ["to-webp", "to-webm", "ico", "trim-image"]
    private static let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var targets: [NimbusTool] {
        Self.toolIDs.compactMap { id in ToolCatalog.tools.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if let run {
                QuickDropRunList(tool: run.tool, acceptance: run.acceptance, items: run.items)
                    .transition(.opacity)
            } else {
                LazyVGrid(columns: Self.columns, spacing: 12) {
                    ForEach(targets) { tool in
                        if let configuration = FileToolConfiguration.configuration(for: tool.id) {
                            QuickDropWell(
                                tool: tool,
                                acceptance: configuration.acceptance,
                                allowsMultipleFiles: configuration.allowsMultipleFiles,
                                onDrop: { files in startRun(tool: tool, acceptance: configuration.acceptance, files: files) }
                            )
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(GlassBackground(cornerRadius: 20))
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
        .scaleEffect(reduceMotion ? 1 : (hasAppeared ? 1 : 0.92), anchor: .topTrailing)
        .offset(y: reduceMotion ? 0 : (hasAppeared ? 0 : 10))
        .opacity(hasAppeared ? 1 : 0)
        .padding(QuickDropMetrics.shadowMargin)
        .animation(.snappy, value: run == nil)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.12)) { hasAppeared = true }
            } else {
                withAnimation(.snappy) { hasAppeared = true }
            }
        }
        .onExitCommand(perform: onDismiss)
        .environmentObject(session)
    }

    /// The whole grid disappears the moment a well accepts files — only one
    /// drop happens at a time, so there is nothing left for the other three
    /// wells to do until this one settles and the panel closes.
    @MainActor
    private func startRun(tool: NimbusTool, acceptance: FileAcceptance, files: [URL]) {
        guard run == nil else { return }
        run = QuickDropRun(tool: tool, acceptance: acceptance, items: files.map { QuickDropRunItem(url: $0, status: .processing) })
        Task { await process(tool: tool, acceptance: acceptance) }
    }

    /// Mirrors `FileToolView.runTool()` — same sidecar call, same
    /// `writeResult` naming/collision handling, sequential rather than
    /// concurrent for the same reason (webP's `perda` preset binary-searches
    /// several full encodes). Every file's row updates as its own request
    /// settles, rather than the whole run waiting to report anything.
    @MainActor
    private func process(tool: NimbusTool, acceptance: FileAcceptance) async {
        var written: [URL] = []
        do {
            let endpoint = try await SidecarProcess.shared.ensureRunning()
            let apiClient = NimbusAPIClient(
                configuration: NimbusConfiguration(apiBaseURL: endpoint.baseURL),
                tokenProvider: SidecarTokenProvider(secret: endpoint.secret)
            )
            let fields = requestFields(for: tool.id)
            let fileFieldName = tool.id == "to-webm" ? "video" : "file"
            let sourceURLs = run?.items.map(\.url) ?? []

            // Same gate as `FileToolView.runTool()`: one unit per file,
            // checked right before that file's request. Without this, Quick
            // Drop's four wells were a free side door around the daily limit
            // — they called the sidecar directly and never touched
            // `UsageQuota` at all.
            // All four wells are file tools, so this is always true today —
            // asked rather than assumed so the rule lives in one place.
            let isMetered = UsageQuota.isMetered(toolID: tool.id)

            fileLoop: for (index, sourceURL) in sourceURLs.enumerated() {
                var consumedCurrentFile = false
                if isMetered {
                    switch await UsageQuota.checkAndConsume() {
                    case let .allowed(consumed):
                        consumedCurrentFile = consumed
                    case let .blocked(message):
                        // Every row from here on never got a chance to run —
                        // same "shares one reason" treatment as the sidecar-down
                        // catch below.
                        let indices = run?.items.indices ?? (0..<0)
                        for remainingIndex in indices where remainingIndex >= index {
                            withAnimation(.snappy) { run?.items[remainingIndex].status = .failed(message) }
                        }
                        break fileLoop
                    }
                }

                do {
                    let fileData = try Data(contentsOf: sourceURL)
                    guard fileData.count <= acceptance.maximumBytes else {
                        throw NimbusAPIError.httpStatus(413, acceptance.maximumSizeMessage)
                    }
                    let (data, response) = try await apiClient.process(
                        tool: tool,
                        file: fileData,
                        filename: sourceURL.lastPathComponent,
                        fileFieldName: fileFieldName,
                        fields: fields
                    )
                    let outputURL = try FileToolView.writeResult(data, response: response, sourceURL: sourceURL)
                    written.append(outputURL)
                    withAnimation(.snappy) { run?.items[index].status = .done }
                } catch {
                    if consumedCurrentFile { UsageQuota.releaseOnFailure() }
                    withAnimation(.snappy) { run?.items[index].status = .failed(error.localizedDescription) }
                }
            }
        } catch {
            // The sidecar itself never came up — every row that never got a
            // chance to run shares that one reason.
            let indices = run?.items.indices ?? (0..<0)
            for index in indices where run?.items[index].status == .processing {
                withAnimation(.snappy) { run?.items[index].status = .failed(error.localizedDescription) }
            }
        }

        if !written.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(written)
        }

        // Held on screen deliberately: long enough for someone glancing over
        // to read every row's outcome, not just catch a flash of green.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        onDismiss()
    }

    /// Mirrors `FileToolView.requestFields`'s shape for the same 3 kinds,
    /// sourced from Quick Drop's own Preferences instead of that view's
    /// per-session `@State` — the whole point of that section existing.
    private func requestFields(for toolID: String) -> [String: String] {
        switch toolID {
        case "to-webp":
            return [
                "webpPreset": (CompressionPreset(rawValue: webPCompression) ?? .glossy).sidecarValue,
                "convertToWebp": webPOperation == "webp" ? "1" : "0"
            ]
        case "to-webm":
            return [
                "webmPreset": (CompressionPreset(rawValue: webMCompression) ?? .glossy).sidecarValue,
                "convertToWebm": webMOperation == "webm" ? "1" : "0"
            ]
        case "ico":
            return ["safeMargin": icoSafeMargin ? "true" : "false"]
        default:
            return [:]
        }
    }
}

/// Replaces the grid for the duration of one drop: the tool's name, then
/// every dropped file's own row, each carrying its own status.
private struct QuickDropRunList: View {
    let tool: NimbusTool
    let acceptance: FileAcceptance
    let items: [QuickDropRunItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tool.name)
                .font(.headline)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        QuickDropRunRow(item: item, fallbackSymbol: acceptance.symbol)
                    }
                }
            }
            .frame(maxHeight: 280)
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
                .saturation(item.status == .done ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var statusText: String {
        switch item.status {
        case .processing: "Processing…"
        case .done: "Done"
        case let .failed(message): message
        }
    }

    private var statusColor: Color {
        if case .failed = item.status { return .orange }
        return .secondary
    }
}

/// A drop target, sibling to `CompactFileField` rather than a reuse of it:
/// `CompactFileField` is a 60pt form row with Replace/Clear links, while a
/// well needs to be a big square that is a comfortable target during a drag.
/// Purely a picker now — accepting files reports them to `QuickDropView`
/// via `onDrop` rather than processing them itself, since a drop replaces
/// the whole grid (this well included) with the run list above.
private struct QuickDropWell: View {
    let tool: NimbusTool
    let acceptance: FileAcceptance
    let allowsMultipleFiles: Bool
    let onDrop: ([URL]) -> Void

    @EnvironmentObject private var session: QuickDropSession

    @State private var isSelecting = false
    @State private var isDropTargeted = false

    var body: some View {
        Button {
            // `NSOpenPanel` is unusable while the app is in the background, and
            // the panel deliberately opens without activating Nimbus — so the
            // app is activated here, at the one moment that needs it.
            NSApp.activate()
            isSelecting = true
        } label: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        // 0.08 and a 1pt dashed border while targeted, matching `FileDropZone`
        // and `CompactFileField`: the panel used a stronger tint and turned its
        // border solid, so the same gesture looked like a different control
        // depending on where you dropped.
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        }
        .dropDestination(for: URL.self) { droppedURLs, _ in
            acceptFiles(droppedURLs)
        } isTargeted: { isDropTargeted = $0 }
        .animation(.snappy, value: isDropTargeted)
        .fileImporter(
            isPresented: $isSelecting,
            allowedContentTypes: acceptance.allowedContentTypes,
            allowsMultipleSelection: allowsMultipleFiles
        ) { result in
            if case let .success(pickedURLs) = result {
                acceptFiles(pickedURLs)
            }
        }
        // `.fileImporter` presents `NSOpenPanel` as a sheet, which resigns
        // the panel's key status; this keeps the panel from closing under
        // the dialog for as long as it's up.
        .onChange(of: isSelecting) { _, isPresented in
            session.importerDepth += isPresented ? 1 : -1
        }
        .accessibilityLabel("\(tool.name), accepts \(acceptance.noun) files")
        .accessibilityValue("Drop \(acceptance.noun) here")
        .help(tool.summary)
    }

    private var content: some View {
        VStack(spacing: 8) {
            Image(systemName: tool.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(tool.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
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
