import AppKit
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
    @State private var quotaBlockedMessage: String?
    @State private var currentStep = 0
    @State private var stepValidity: [Bool] = []

    /// nil for every form short enough to stay on one page — which is all of
    /// them but Contract PDF and Copy Generator.
    private var steps: [String]? { configuration.kind.steps }
    private var isLastStep: Bool { currentStep >= (steps?.count ?? 1) - 1 }
    /// Unreached steps report false, so "Next" stays disabled until the step
    /// on screen is actually filled in.
    private var currentStepIsValid: Bool {
        stepValidity.indices.contains(currentStep) ? stepValidity[currentStep] : false
    }

    private let focusRingInset: CGFloat = 4

    /// Owned here rather than in the fields slice because the picker it drives
    /// is rendered beside the action button, the way file tools carry their
    /// options.
    @State private var minifyAction = "minify"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(.title.bold())
                // The step line replaces the summary rather than stacking
                // under it: once someone is three steps into a form, which
                // step they're on is the more useful of the two, and the
                // summary has already done its job.
                if let steps, result == nil {
                    Text("Step \(currentStep + 1) of \(steps.count) · \(steps[currentStep])")
                        .foregroundStyle(.secondary)
                } else {
                    Text(tool.summary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, isSidebarVisible ? 0 : 52)
            .padding(.horizontal, focusRingInset)

            ZStack {
                // A form whose whole body is one code editor has nothing to
                // scroll — wrapping it would cap the editor at its ideal height
                // and leave the rest of the pane empty.
                Group {
                    if configuration.kind.isMinifyTool {
                        VStack(alignment: .leading, spacing: 20) {
                            fieldsForSlice
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(focusRingInset)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                fieldsForSlice
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(focusRingInset)
                        }
                    }
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
                    if configuration.kind.isMinifyTool {
                        Picker("Action", selection: $minifyAction) {
                            Text("Minify").tag("minify")
                            Text("Unminify").tag("unminify")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 110)
                        .help("Action")
                        .disabled(isProcessing)
                    }
                    if steps != nil && currentStep > 0 {
                        Button("Back") {
                            withAnimation(.snappy) { currentStep -= 1 }
                        }
                        .disabled(isProcessing)
                    }
                    // The action button only exists on the last step, so
                    // there's never a moment where both "Next" and "run this"
                    // are on screen competing for the same Return key.
                    if steps != nil && !isLastStep {
                        Button("Next") {
                            withAnimation(.snappy) { currentStep += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!currentStepIsValid)
                    } else {
                        Button(configuration.actionTitle) {
                            runTask = Task { await runTool() }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSubmit || isProcessing)
                    }
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
        .task(id: minifyAction) {
            guard configuration.kind.isMinifyTool else { return }
            fields["action"] = minifyAction
        }
        .padding(.horizontal, 24 - focusRingInset)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .alert(
            "Daily Limit Reached",
            isPresented: Binding(
                get: { quotaBlockedMessage != nil },
                set: { if !$0 { quotaBlockedMessage = nil } }
            )
        ) {
            Button("Upgrade") { NSWorkspace.shared.open(UsageQuota.upgradeURL) }
            Button("OK", role: .cancel) { }
        } message: {
            Text(quotaBlockedMessage ?? "")
        }
    }

    @ViewBuilder
    private var fieldsForSlice: some View {
        switch configuration.kind.slice {
        case .sliceA:
            FormFieldsSliceA(
                kind: configuration.kind, canSubmit: $canSubmit, fields: $fields, files: $files,
                step: currentStep, stepValidity: $stepValidity
            )
        case .sliceB:
            FormFieldsSliceB(
                kind: configuration.kind, canSubmit: $canSubmit, fields: $fields, files: $files,
                step: currentStep, stepValidity: $stepValidity
            )
        }
    }

    @MainActor
    private func runTool() async {
        isProcessing = true
        defer { isProcessing = false }

        let consumedUnit: Bool
        switch await UsageQuota.checkAndConsume() {
        case let .allowed(consumed):
            consumedUnit = consumed
        case let .blocked(message):
            quotaBlockedMessage = message
            return
        }

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
        } catch is CancellationError {
            if consumedUnit { UsageQuota.releaseOnFailure() }
        } catch {
            if consumedUnit { UsageQuota.releaseOnFailure() }
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
