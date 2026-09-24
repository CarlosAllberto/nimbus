import Foundation

/// Where a request to open a tool came from. Every entry point goes through
/// `ToolLauncher`, so the window shows and focuses the same way for all of them.
enum ToolOpenSource {
    case quickSearch, coreSpotlight, deepLink, finderAction
}

struct ToolOpenRequest: Equatable {
    let toolID: String
    var files: [URL] = []
    let source: ToolOpenSource
}

/// The single path for opening a tool in the main window. Callers `open(_:)`;
/// `MainWindowView` `consume()`s the pending request when it navigates, so a
/// request made while the window is closed or on the sign-in gate waits for a
/// view that can act on it.
@MainActor
final class ToolLauncher: ObservableObject {
    static let shared = ToolLauncher()
    private init() {}

    @Published private(set) var pending: ToolOpenRequest?

    func open(_ request: ToolOpenRequest) {
        pending = request
    }

    func consume() -> ToolOpenRequest? {
        defer { pending = nil }
        return pending
    }
}

extension ToolOpenRequest {
    /// `nimbus://open?tool=<id>[&file=<percent-encoded absolute path>]...`.
    /// Anything that fails validation is dropped silently: an unknown tool
    /// yields nil, a bad file is left out. Never runs the tool, only names it.
    init?(deepLink url: URL) {
        guard url.scheme?.lowercased() == "nimbus", url.host?.lowercased() == "open",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let toolID = items.first(where: { $0.name == "tool" })?.value,
              ToolCatalog.tools.contains(where: { $0.id == toolID })
        else { return nil }

        var files: [URL] = []
        if let configuration = FileToolConfiguration.configuration(for: toolID) {
            for item in items where item.name == "file" {
                guard let path = item.value, path.hasPrefix("/") else { continue }
                let file = URL(fileURLWithPath: path)
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true, configuration.acceptance.accepts(file) else { continue }
                files.append(file)
            }
            if !configuration.allowsMultipleFiles { files = Array(files.prefix(1)) }
        }
        self.init(toolID: toolID, files: files, source: .deepLink)
    }
}
