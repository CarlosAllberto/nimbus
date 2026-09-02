import SwiftUI
import UniformTypeIdentifiers

struct FormToolView: View {
    let tool: NimbusTool
    let configuration: FormToolConfiguration
    let isSidebarVisible: Bool

    @State private var canSubmit = false
    @State private var fields: [String: String] = [:]
    @State private var files: [String: URL] = [:]
    @State private var isProcessing = false
    @State private var result: FormRunResult?
    @State private var runTask: Task<Void, Never>?

    private let focusRingInset: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(.title.bold())
                Text(tool.summary)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, isSidebarVisible ? 0 : 52)
            .padding(.horizontal, focusRingInset)

            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        fieldsForSlice
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(focusRingInset)
                }
                .opacity(result == nil ? 1 : 0)
                .allowsHitTesting(result == nil)

                if let result {
                    FormResultView(result: result)
                        .transition(.opacity)
                }
            }
            .layoutPriority(1)

            // The primary action stays in this exact spot whether it's about to
            // run the tool or about to dismiss the result — only its label(s)
            // change, so the result never needs its own "Done" button floating
            // somewhere else in the panel.
            HStack(spacing: 10) {
                Spacer()
                if let result {
                    if case let .file(data, suggestedFilename, contentType) = result {
                        Button("Save…") {
                            saveToFile(data: data, suggestedFilename: suggestedFilename, contentType: UTType(mimeType: contentType) ?? .data)
                        }
                    }
                    Button("Done") {
                        withAnimation(.snappy) { self.result = nil }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    if isProcessing {
                        ProgressView().controlSize(.small)
                    }
                    Button(configuration.actionTitle) {
                        runTask = Task { await runTool() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit || isProcessing)
                }
            }
            .padding(.horizontal, focusRingInset)
            .animation(.snappy, value: isProcessing)
        }
        // 460 to match `FileToolView`: a narrower block than the pane gets
        // centred, and that offset is what carries the header clear of the
        // sidebar toggle when the sidebar is hidden. At 560 the block sat
        // further left and the title ran under the button — the file tools were
        // only ever fine because of the width they happen to use.
        .frame(maxWidth: result == nil ? 460 : .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24 - focusRingInset)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var fieldsForSlice: some View {
        switch configuration.kind.slice {
        case .sliceA:
            FormFieldsSliceA(kind: configuration.kind, canSubmit: $canSubmit, fields: $fields, files: $files)
        case .sliceB:
            FormFieldsSliceB(kind: configuration.kind, canSubmit: $canSubmit, fields: $fields, files: $files)
        }
    }

    @MainActor
    private func runTool() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let endpoint = try await SidecarProcess.shared.ensureRunning()
            let apiClient = NimbusAPIClient(
                configuration: NimbusConfiguration(apiBaseURL: endpoint.baseURL),
                tokenProvider: SidecarTokenProvider(secret: endpoint.secret)
            )
            var extraFiles: [NimbusExtraFile] = []
            for (fieldName, url) in files {
                extraFiles.append(NimbusExtraFile(
                    fieldName: fieldName,
                    data: try Data(contentsOf: url),
                    filename: url.lastPathComponent
                ))
            }
            let (data, response) = try await apiClient.processForm(tool: tool, fields: fields, files: extraFiles)
            withAnimation(.snappy) { result = Self.interpretResult(data: data, response: response, toolID: tool.id) }
        } catch {
            withAnimation(.snappy) { result = .error(error.localizedDescription) }
        }
    }

    /// A JSON body becomes the data panel (composed per-tool downstream); anything
    /// else (QR Code's image, the PDF binary) becomes a file to preview and save.
    /// Pretty-printing moved to `RawJSONFallbackView`; we keep the raw bytes here
    /// so the composer can decode by tool.
    private static func interpretResult(data: Data, response: URLResponse, toolID: String) -> FormRunResult {
        guard let http = response as? HTTPURLResponse else {
            return .error("Nimbus returned an invalid response.")
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";").first.map(String.init) ?? "application/octet-stream"

        if contentType == "application/json" {
            return .data(json: data, toolID: toolID)
        }

        let fileExtension = UTType(mimeType: contentType)?.preferredFilenameExtension ?? "bin"
        return .file(data: data, suggestedFilename: "\(toolID)-nimbus.\(fileExtension)", contentType: contentType)
    }
}
