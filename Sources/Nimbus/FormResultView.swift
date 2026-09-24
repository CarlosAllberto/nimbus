import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FormRunResult: Equatable {
    case data(json: Data, toolID: String)
    case file(data: Data, suggestedFilename: String, contentType: String)
    case error(String)
}

/// The generic result panel every form tool shares: a successful JSON answer
/// routes to a per-tool composer (`FormResultSliceA`/`FormResultSliceB`,
/// picked by `FormToolKind.slice` — same split `FormFieldsSliceA`/`B` already
/// use). A tool id this build doesn't recognize, or a composer whose
/// `JSONDecoder.decode` fails, falls back to `RawJSONFallbackView` — the
/// pretty-printed panel this whole view used to be.
///
/// No card chrome and no action buttons here on purpose: this view only
/// renders content. `FormToolView` swaps its submit button for "Save…"/"Done"
/// in the same bottom-right spot once a result exists, so the primary action
/// never moves and the result gets the full width of the panel instead of
/// sitting in a second, narrower card inside it.
struct FormResultView: View {
    let result: FormRunResult

    @State private var hasAppeared = false

    var body: some View {
        Group {
            switch result {
            case let .data(json, toolID):
                dataResult(json: json, toolID: toolID)
            case let .file(data, suggestedFilename, contentType):
                fileResult(data: data, suggestedFilename: suggestedFilename, contentType: contentType)
            case let .error(message):
                errorResult(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(hasAppeared ? 1 : 0.96)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear { withAnimation(.snappy) { hasAppeared = true } }
    }

    @ViewBuilder
    private func dataResult(json: Data, toolID: String) -> some View {
        // These results are a single code block that scrolls on its own,
        // and it should have the height the panel can spare. Nesting it in an
        // outer scroll view would both cap it at its ideal height and put one
        // scroller inside another.
        if FormToolKind(rawValue: toolID)?.resultFillsHeight == true {
            composedResult(json: json, toolID: toolID)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } else {
            ScrollView {
                composedResult(json: json, toolID: toolID)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func composedResult(json: Data, toolID: String) -> some View {
        if let kind = FormToolKind(rawValue: toolID) {
            switch kind.slice {
            case .sliceA: FormResultSliceA(kind: kind, json: json)
            case .sliceB: FormResultSliceB(kind: kind, json: json)
            }
        } else {
            RawJSONFallbackView(json: json)
        }
    }

    @ViewBuilder
    private func fileResult(data: Data, suggestedFilename: String, contentType: String) -> some View {
        VStack(spacing: 12) {
            if UTType(mimeType: contentType)?.conforms(to: .image) == true, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 160, maxHeight: 160)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(suggestedFilename)
                .font(.headline)
        }
    }

    @ViewBuilder
    private func errorResult(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}
