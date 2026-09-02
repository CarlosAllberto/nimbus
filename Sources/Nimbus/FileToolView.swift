import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FileToolKind: String, CaseIterable {
    case webP = "to-webp"
    case ico
    case webM = "to-webm"
    case deviceWrapper = "device-wrapper"
    case trimImage = "trim-image"
    case convert
    case resize
    case resizeVideo = "resize-video"
    case paletteFromImage = "palette-from-image"
    case fontConvert = "font-convert"
}

struct FileToolConfiguration: Equatable {
    let kind: FileToolKind
    let acceptance: FileAcceptance
    let allowsMultipleFiles: Bool
    let actionTitle: String

    var defaultOutputFormat: String? {
        switch kind {
        case .webP: "webp"
        case .webM: "webm"
        case .convert: "png"
        case .fontConvert: "ttf"
        default: nil
        }
    }

    var defaultDimension: Int? {
        switch kind {
        case .resize, .resizeVideo: 640
        default: nil
        }
    }

    var defaultPaletteColorCount: Int? {
        kind == .paletteFromImage ? 5 : nil
    }

    func isDimensionValid(_ value: Int) -> Bool {
        switch kind {
        case .resize, .resizeVideo: value >= 50
        default: true
        }
    }

    static func configuration(for toolID: String) -> FileToolConfiguration? {
        guard let kind = FileToolKind(rawValue: toolID) else { return nil }

        switch kind {
        case .webP:
            return .init(kind: kind, acceptance: .image, allowsMultipleFiles: true, actionTitle: "Compress Images")
        case .ico:
            return .init(kind: kind, acceptance: .image, allowsMultipleFiles: false, actionTitle: "Create Favicon")
        case .webM:
            return .init(kind: kind, acceptance: .video, allowsMultipleFiles: false, actionTitle: "Compress Video")
        case .deviceWrapper:
            return .init(kind: kind, acceptance: .image, allowsMultipleFiles: false, actionTitle: "Create Wrapper")
        case .trimImage:
            return .init(kind: kind, acceptance: .image, allowsMultipleFiles: false, actionTitle: "Trim Image")
        case .convert:
            return .init(kind: kind, acceptance: .image, allowsMultipleFiles: false, actionTitle: "Convert Image")
        case .resize:
            return .init(kind: kind, acceptance: .image, allowsMultipleFiles: false, actionTitle: "Resize Image")
        case .resizeVideo:
            return .init(kind: kind, acceptance: .video, allowsMultipleFiles: false, actionTitle: "Resize Video")
        case .paletteFromImage:
            return .init(kind: kind, acceptance: .image, allowsMultipleFiles: false, actionTitle: "Extract Palette")
        case .fontConvert:
            return .init(kind: kind, acceptance: .font, allowsMultipleFiles: false, actionTitle: "Convert Font")
        }
    }
}

/// Internal, not private: `PreferencesView`'s Quick Drop section and
/// `QuickDropView`'s well both need it too — one picks the preset, the
/// other turns it into the sidecar's PT-BR preset string.
enum CompressionPreset: String, CaseIterable, Identifiable {
    case glossy
    case lossy
    case lossless

    var id: Self { self }

    var title: String {
        switch self {
        case .glossy: "Glossy (Recommended)"
        case .lossy: "Lossy"
        case .lossless: "Lossless"
        }
    }

    /// The sidecar's own vocabulary for this preset — ported verbatim from
    /// the web app, so it stays PT-BR regardless of the app's own English UI.
    var sidecarValue: String {
        switch self {
        case .lossless: "sem-perdas"
        case .glossy: "lustroso"
        case .lossy: "perda"
        }
    }

    var help: String {
        switch self {
        case .glossy: "Balances high visual quality with a smaller file."
        case .lossy: "Produces the smallest file with some quality loss."
        case .lossless: "Preserves every detail and produces a larger file."
        }
    }
}

private enum ResizeDimension: String, CaseIterable, Identifiable {
    case width
    case height

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

/// Per-file state during a run, so each thumbnail can show where it stands
/// instead of leaving one counter to speak for the whole batch.
enum FileRunStatus: Equatable {
    case processing
    case done
    case failed
}

/// One swatch from Palette From Image. The sidecar already returns the strings
/// ready to paste, so nothing is reformatted on this side.
struct PaletteColor: Decodable, Equatable, Identifiable {
    let hex: String
    let rgb: String
    let weight: Int

    var id: String { hex }
}

private struct PaletteResponse: Decodable {
    let colors: [PaletteColor]
}

/// What a finished run leaves behind. It persists until the user dismissed it
/// or drops new files — a confirmation that vanishes on a timer takes the only
/// route back to the result with it. Most tools leave files; the ones that
/// answer with data leave that instead.
private struct RunCompletion: Equatable {
    var outputs: [URL] = []
    var palette: [PaletteColor] = []
    var wasCancelled = false
}

struct FileToolView: View {
    let tool: NimbusTool
    let configuration: FileToolConfiguration
    let isSidebarVisible: Bool

    @State private var selectedFiles: [URL] = []
    @State private var isSelectingFiles = false
    @State private var isDropTargeted = false
    @State private var importErrorMessage: String?
    @State private var isProcessing = false
    @State private var processedCount = 0
    @State private var runTask: Task<Void, Never>?
    @State private var fileStatuses: [URL: FileRunStatus] = [:]
    @State private var completion: RunCompletion?
    @State private var processingErrorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var outputFormat = "webp"
    @State private var compressionPreset: CompressionPreset = .glossy
    @State private var safeMargin = false
    @State private var deviceOS = "macos"
    @State private var deviceBackground = "transparent"
    @State private var backgroundImageURL: URL?
    @State private var resizeDimension: ResizeDimension = .width
    @State private var dimension = 640
    @State private var paletteColorCount = 5

    init(tool: NimbusTool, configuration: FileToolConfiguration, isSidebarVisible: Bool) {
        self.tool = tool
        self.configuration = configuration
        self.isSidebarVisible = isSidebarVisible

        _outputFormat = State(initialValue: configuration.defaultOutputFormat ?? "webp")
        _dimension = State(initialValue: configuration.defaultDimension ?? 640)
        _paletteColorCount = State(initialValue: configuration.defaultPaletteColorCount ?? 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(.title.bold())
                Text(tool.summary)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, isSidebarVisible ? 0 : 52)

            // The background picker is a second file input, so it belongs with
            // the drop zone rather than with the option pickers below — the
            // body's 18pt rhythm separates groups, and these two are one group.
            VStack(alignment: .leading, spacing: 8) {
            ZStack {
                FileDropZone(
                    urls: $selectedFiles,
                    isTargeted: $isDropTargeted,
                    acceptance: configuration.acceptance,
                    allowsMultipleFiles: configuration.allowsMultipleFiles,
                    statuses: fileStatuses,
                    isLocked: isProcessing,
                    chooseFiles: { isSelectingFiles = true },
                    acceptDrop: acceptFiles
                )
                .opacity(completion == nil ? 1 : 0)
                // Hidden but still mounted, so it must not swallow a drop
                // aimed at the panel covering it.
                .allowsHitTesting(completion == nil)

                if let completion {
                    CompletionPanel(
                        outputs: completion.outputs,
                        palette: completion.palette,
                        wasCancelled: completion.wasCancelled,
                        noun: configuration.acceptance.noun,
                        dismiss: { withAnimation(motion) { self.completion = nil } }
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 170, maxHeight: .infinity)
            .layoutPriority(1)

                if configuration.kind == .deviceWrapper, deviceBackground == "custom" {
                    CompactFileField(label: "Background Image", acceptance: .image, url: $backgroundImageURL)
                        .transition(backgroundFieldTransition)
                }
            }
            .layoutPriority(1)
            .animation(motion, value: deviceBackground)

            actionBar
        }
        .frame(maxWidth: 460, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .fileImporter(
            isPresented: $isSelectingFiles,
            allowedContentTypes: configuration.acceptance.allowedContentTypes,
            allowsMultipleSelection: configuration.allowsMultipleFiles
        ) { result in
            switch result {
            case let .success(urls):
                _ = acceptFiles(urls)
            case let .failure(error):
                importErrorMessage = error.localizedDescription
            }
        }
        .alert(
            "Couldn't Add Files",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage ?? "The selected files couldn't be read.")
        }
        .alert(
            "Couldn't Process File",
            isPresented: Binding(
                get: { processingErrorMessage != nil },
                set: { if !$0 { processingErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(processingErrorMessage ?? "Something went wrong.")
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 10) {
            // Progress lives beside the action, never inside it: the primary
            // button keeps saying what it does, the way every long operation in
            // the system behaves.
            if isProcessing {
                HStack(spacing: 10) {
                    ProgressView(value: Double(processedCount), total: Double(max(selectedFiles.count, 1)))
                        .progressViewStyle(.linear)
                    Text("\(min(processedCount + 1, selectedFiles.count)) of \(selectedFiles.count)")
                        .font(.callout.monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                controls

                if isProcessing {
                    Button("Cancel") { runTask?.cancel() }
                        .buttonStyle(.bordered)
                }

                Button {
                    guard requestFields != nil else { return }
                    runTask = Task { await runTool() }
                } label: {
                    Text(configuration.actionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!canSubmit || isProcessing)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(motion, value: isProcessing)
        .animation(motion, value: processedCount)
    }

    /// The field's frame appears at once — that is what makes the drop zone
    /// above shrink — but fading it in only once that movement has settled
    /// keeps it from showing up on top of a layout still moving. Removal is not
    /// delayed: fading out as the gap closes reads as one motion, while a
    /// delayed exit would leave the field hanging over the collapse.
    private var backgroundFieldTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(reduceMotion ? motion : motion.delay(0.18)),
            removal: .opacity.animation(motion)
        )
    }

    /// Honours Reduce Motion everywhere in this view, the way the Quick Drop
    /// panel already does.
    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .snappy
    }

    /// The multipart fields each wired tool sends, mirroring the shape of the
    /// `controls` switch above.
    private var requestFields: [String: String]? {
        switch configuration.kind {
        case .webP:
            return [
                "webpPreset": compressionPreset.sidecarValue,
                "convertToWebp": outputFormat == "webp" ? "1" : "0"
            ]
        case .trimImage:
            return [:]
        case .convert:
            return ["format": outputFormat]
        case .resize:
            return ["width": String(dimension), "resizeBy": resizeDimension.rawValue]
        case .ico:
            return ["safeMargin": safeMargin ? "true" : "false"]
        case .paletteFromImage:
            return ["count": String(paletteColorCount)]
        case .fontConvert:
            return ["targetFormat": outputFormat]
        case .webM:
            return [
                "webmPreset": compressionPreset.sidecarValue,
                "convertToWebm": outputFormat == "webm" ? "1" : "0"
            ]
        case .resizeVideo:
            return ["width": String(dimension), "resizeBy": resizeDimension.rawValue]
        case .deviceWrapper:
            return ["os": deviceOS, "bg": deviceBackground == "transparent" ? "transparent" : "image"]
        }
    }

    /// Extra multipart parts beyond the single primary file. Only Device
    /// Wrapper needs one so far — its background image, sent only when the
    /// user actually chose one; the sidecar falls back to a bundled asset
    /// when the part is absent, so omitting it is a normal request, not a
    /// degraded one.
    private func extraFiles() throws -> [NimbusExtraFile] {
        switch configuration.kind {
        case .deviceWrapper:
            guard deviceBackground == "custom", let backgroundImageURL else { return [] }
            return [NimbusExtraFile(
                fieldName: "background",
                data: try Data(contentsOf: backgroundImageURL),
                filename: backgroundImageURL.lastPathComponent
            )]
        default:
            return []
        }
    }

    /// The video routes call the main part `video`; everything else calls it
    /// `file`. The web app names them that way, so the sidecar does too.
    private var fileFieldName: String {
        switch configuration.kind {
        case .webM, .resizeVideo: "video"
        default: "file"
        }
    }

    @MainActor
    private func runTool() async {
        let sources = selectedFiles
        guard !sources.isEmpty else { return }
        isProcessing = true
        processedCount = 0
        defer { isProcessing = false }

        // Sequential, not concurrent: this tool accepts a whole batch, and the
        // sidecar's `perda` preset binary-searches several full encodes per
        // image. Firing them all at once would just contend for the same cores
        // and make the progress count meaningless.
        var written: [URL] = []
        var palette: [PaletteColor] = []
        var cancelled = false
        withAnimation(motion) {
            completion = nil
            fileStatuses = [:]
        }
        do {
            let endpoint = try await SidecarProcess.shared.ensureRunning()
            let apiClient = NimbusAPIClient(
                configuration: NimbusConfiguration(apiBaseURL: endpoint.baseURL),
                tokenProvider: SidecarTokenProvider(secret: endpoint.secret)
            )

            let fields = requestFields ?? [:]
            let extras = try extraFiles()

            for sourceURL in sources {
                // Checked between files, not mid-encode: a half-written output
                // would be worse than finishing the one already in flight.
                if Task.isCancelled { cancelled = true; break }
                withAnimation(motion) { fileStatuses[sourceURL] = .processing }

                let fileData = try Data(contentsOf: sourceURL)
                guard fileData.count <= configuration.acceptance.maximumBytes else {
                    throw NimbusAPIError.httpStatus(413, configuration.acceptance.maximumSizeMessage)
                }
                let (data, response) = try await apiClient.process(
                    tool: tool,
                    file: fileData,
                    filename: sourceURL.lastPathComponent,
                    fileFieldName: fileFieldName,
                    fields: fields,
                    extraFiles: extras
                )
                if configuration.kind == .paletteFromImage {
                    palette = try JSONDecoder().decode(PaletteResponse.self, from: data).colors
                } else {
                    written.append(try Self.writeResult(data, response: response, sourceURL: sourceURL))
                }
                withAnimation(motion) {
                    fileStatuses[sourceURL] = .done
                    processedCount += 1
                }
            }
        } catch is CancellationError {
            cancelled = true
        } catch {
            // Whatever already landed on disk stays there; the message names
            // the file that stopped the batch, and its tile stays marked.
            let failedIndex = written.count
            if failedIndex < sources.count {
                withAnimation(motion) { fileStatuses[sources[failedIndex]] = .failed }
                processingErrorMessage = "\(sources[failedIndex].lastPathComponent): \(error.localizedDescription)"
            } else {
                processingErrorMessage = error.localizedDescription
            }
        }

        if !written.isEmpty || !palette.isEmpty {
            if !written.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(written)
            }
            withAnimation(motion) {
                selectedFiles.removeAll()
                fileStatuses = [:]
                completion = RunCompletion(outputs: written, palette: palette, wasCancelled: cancelled)
            }
        }
    }

    /// Written beside the source file with a suffix, never over a save
    /// panel — the extension comes from the response's `Content-Type`, not
    /// the input filename, since turning conversion off keeps the source
    /// format while turning it on produces `.webp` regardless of input.
    static func writeResult(_ data: Data, response: URLResponse, sourceURL: URL) throws -> URL {
        guard let http = response as? HTTPURLResponse else { throw NimbusAPIError.invalidResponse }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";").first.map(String.init) ?? "application/octet-stream"
        let fileExtension = UTType(mimeType: contentType)?.preferredFilenameExtension ?? sourceURL.pathExtension

        let directory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent

        var destination = directory.appendingPathComponent("\(baseName)-nimbus").appendingPathExtension(fileExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory
                .appendingPathComponent("\(baseName)-nimbus-\(suffix)")
                .appendingPathExtension(fileExtension)
            suffix += 1
        }

        try data.write(to: destination)
        return destination
    }

    @ViewBuilder
    private var controls: some View {
        switch configuration.kind {
        case .webP:
            menuPicker("Operation", selection: $outputFormat, options: [
                ("webp", "To WebP"), ("original", "Compress")
            ], width: 110)
            compressionPicker

        case .ico:
            Picker("Safe Margin", selection: $safeMargin) {
                Text("Margin Off").tag(false)
                Text("Margin On").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 175)
            .accessibilityLabel("Safe Margin")
            .help("Add safe spacing around the icon artwork")

        case .webM:
            menuPicker("Operation", selection: $outputFormat, options: [
                ("webm", "To WebM"), ("original", "Compress")
            ], width: 110)
            compressionPicker

        case .deviceWrapper:
            menuPicker("Device", selection: $deviceOS, options: [
                ("macos", "macOS"), ("windows", "Windows")
            ], width: 110)
            menuPicker("Background", selection: $deviceBackground, options: [
                ("transparent", "Transparent"),
                ("image", "Built-in"),
                ("custom", "Custom…")
            ], width: 110)

        case .trimImage:
            EmptyView()

        case .convert:
            menuPicker("Output Format", selection: $outputFormat, options: [
                ("png", "PNG"), ("jpg", "JPG"), ("webp", "WebP")
            ], width: 90)

        case .resize, .resizeVideo:
            Picker("Resize By", selection: $resizeDimension) {
                ForEach(ResizeDimension.allCases) { dimension in
                    Text(dimension.title).tag(dimension)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 130)

            TextField("Pixels", value: $dimension, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(resizeDimension.title) in pixels")

        case .paletteFromImage:
            Picker("Color Count", selection: $paletteColorCount) {
                ForEach(2...12, id: \.self) { count in
                    Text("\(count) colors").tag(count)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 100)

        case .fontConvert:
            menuPicker("Output Format", selection: $outputFormat, options: [
                ("ttf", "TTF"), ("otf", "OTF"), ("woff", "WOFF"),
                ("woff2", "WOFF2"), ("eot", "EOT")
            ], width: 90)
        }
    }

    private var compressionPicker: some View {
        Picker("Quality", selection: $compressionPreset) {
            ForEach(CompressionPreset.allCases) { preset in
                Text(preset.title).tag(preset)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 170)
        .help(compressionPreset.help)
    }

    private func menuPicker(
        _ label: String,
        selection: Binding<String>,
        options: [(String, String)],
        width: CGFloat
    ) -> some View {
        Picker(label, selection: selection) {
            ForEach(options, id: \.0) { option in
                Text(option.1).tag(option.0)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: width)
        .help(label)
    }

    private var canSubmit: Bool {
        guard !selectedFiles.isEmpty else { return false }
        guard configuration.isDimensionValid(dimension) else { return false }
        // Only "Custom…" needs a file: "Built-in" is a complete choice on its
        // own, so the button must not sit greyed out with nothing explaining why.
        return configuration.kind != .deviceWrapper || deviceBackground != "custom" || backgroundImageURL != nil
    }

    private func acceptFiles(_ urls: [URL]) -> Bool {
        let acceptedFiles = urls.filter(configuration.acceptance.accepts)
        guard !acceptedFiles.isEmpty else {
            importErrorMessage = "Choose a supported \(configuration.acceptance.noun) file."
            return false
        }

        withAnimation(motion) {
            // New input supersedes the last run's confirmation.
            completion = nil
            if configuration.allowsMultipleFiles {
                let existingURLs = Set(selectedFiles)
                selectedFiles.append(contentsOf: acceptedFiles.filter { !existingURLs.contains($0) })
            } else {
                selectedFiles = [acceptedFiles[0]]
            }
        }

        if acceptedFiles.count != urls.count {
            importErrorMessage = "Some unsupported files were skipped."
        }
        return true
    }
}

/// Takes the drop zone's place after a run and stays there until dismissed or
/// until new files arrive. It is not on a timer: the route back to the output
/// has to outlive a glance away from the screen.
private struct CompletionPanel: View {
    let outputs: [URL]
    var palette: [PaletteColor] = []
    let wasCancelled: Bool
    let noun: String
    let dismiss: () -> Void

    @State private var hasAppeared = false
    @State private var copiedHex: String?

    private var headline: String {
        if !palette.isEmpty {
            return "\(palette.count) colors extracted"
        }
        let count = outputs.count
        let subject = count == 1 ? noun : "\(noun)s"
        return wasCancelled ? "Stopped after \(count) \(subject)" : "\(count) \(subject) saved"
    }

    var body: some View {
        VStack(spacing: 12) {
            if palette.isEmpty {
                Image(systemName: wasCancelled ? "stop.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(wasCancelled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .symbolEffect(.bounce, value: hasAppeared)
            }

            Text(headline)
                .font(.headline)

            if !palette.isEmpty {
                PaletteSwatches(colors: palette, copiedHex: $copiedHex)
            }

            HStack(spacing: 12) {
                if !outputs.isEmpty {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(outputs)
                    }
                }
                if !palette.isEmpty {
                    Button("Copy All") {
                        copy(palette.map(\.hex).joined(separator: "\n"), label: "all")
                    }
                }
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(hasAppeared ? 1 : 0.96)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear { withAnimation(.snappy) { hasAppeared = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headline)
    }

    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.snappy) { copiedHex = label }
    }
}

/// The extracted colors, ordered by how much of the image they cover. Clicking
/// one copies its hex — the reason to run this tool at all is to paste the
/// value somewhere.
private struct PaletteSwatches: View {
    let colors: [PaletteColor]
    @Binding var copiedHex: String?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(colors) { color in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(color.hex, forType: .string)
                        withAnimation(.snappy) { copiedHex = color.hex }
                    } label: {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: color.hex) ?? .gray)
                            .frame(width: 40, height: 40)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                            }
                            .overlay {
                                if copiedHex == color.hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(color.hex)
                    .accessibilityLabel("\(color.hex), click to copy")
                }
            }

            Text(copiedHex == nil ? "Click a color to copy its hex" : "Copied \(copiedHex == "all" ? "all values" : copiedHex ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }
}

extension Color {
    /// Parses the `#rrggbb` the sidecar sends. Returns nil rather than guessing
    /// on anything else.
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct FileDropZone: View {
    @Binding var urls: [URL]
    @Binding var isTargeted: Bool
    let acceptance: FileAcceptance
    let allowsMultipleFiles: Bool
    let statuses: [URL: FileRunStatus]
    let isLocked: Bool
    let chooseFiles: () -> Void
    let acceptDrop: ([URL]) -> Bool

    var body: some View {
        Group {
            if isTargeted {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop to add \(acceptance.noun)\(allowsMultipleFiles ? "s" : "")")
                        .font(.headline)
                }
            } else if urls.isEmpty {
                Button(action: chooseFiles) {
                    VStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Drop \(acceptance.noun)\(allowsMultipleFiles ? "s" : "") here")
                            .font(.headline)
                        Text("or click to choose \(allowsMultipleFiles ? "files" : "a file")")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose \(acceptance.noun) files")
            } else {
                VStack(spacing: 10) {
                    SelectedFilesPreview(
                        urls: urls,
                        fallbackSymbol: acceptance.symbol,
                        statuses: statuses,
                        isLocked: isLocked
                    ) { url in
                        withAnimation(.snappy) { urls.removeAll { $0 == url } }
                    }

                    HStack(spacing: 12) {
                        Text("\(urls.count) file\(urls.count == 1 ? "" : "s") selected")
                            .font(.headline)
                        Button(allowsMultipleFiles ? "Add Files…" : "Replace…", action: chooseFiles)
                            .buttonStyle(.link)
                            .disabled(isLocked)
                        if urls.count > 1 {
                            Button("Clear") {
                                withAnimation(.snappy) { urls.removeAll() }
                            }
                            .buttonStyle(.link)
                            .disabled(isLocked)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
        .dropDestination(for: URL.self) { droppedURLs, _ in
            acceptDrop(droppedURLs)
        } isTargeted: { isTargeted = $0 }
        .animation(.snappy, value: isTargeted)
    }
}

private struct SelectedFilesPreview: View {
    let urls: [URL]
    let fallbackSymbol: String
    let statuses: [URL: FileRunStatus]
    let isLocked: Bool
    let remove: (URL) -> Void

    var body: some View {
        if let onlyURL = urls.first, urls.count == 1 {
            FileThumbnail(
                url: onlyURL,
                size: 120,
                fallbackSymbol: fallbackSymbol,
                status: statuses[onlyURL],
                isLocked: isLocked
            ) {
                remove(onlyURL)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 82), spacing: 10)], spacing: 10) {
                    ForEach(urls, id: \.self) { url in
                        FileThumbnail(
                            url: url,
                            size: 72,
                            fallbackSymbol: fallbackSymbol,
                            status: statuses[url],
                            isLocked: isLocked
                        ) {
                            remove(url)
                        }
                    }
                }
                .padding(4)
            }
        }
    }
}

private struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    let fallbackSymbol: String
    let status: FileRunStatus?
    let isLocked: Bool
    let remove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FileThumbnailImage(url: url, size: size, fallbackSymbol: fallbackSymbol)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                // Each tile carries its own state, so the grid itself shows the
                // batch advancing instead of a lone counter speaking for it.
                .overlay { statusOverlay }
                .saturation(status == .done ? 0.4 : 1)

            if !isLocked {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(url.lastPathComponent)")
                .padding(4)
            }
        }
        .help(url.lastPathComponent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityValue(statusDescription)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch status {
        case .processing:
            ZStack {
                Color.black.opacity(0.35)
                ProgressView().controlSize(.small)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .done:
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: size > 100 ? 26 : 18))
                    .padding(5)
            }
        case .failed:
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                Image(systemName: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .font(.system(size: size > 100 ? 26 : 18))
                    .padding(5)
            }
        case nil:
            EmptyView()
        }
    }

    private var statusDescription: String {
        switch status {
        case .processing: "Processing"
        case .done: "Done"
        case .failed: "Failed"
        case nil: "Waiting"
        }
    }
}
