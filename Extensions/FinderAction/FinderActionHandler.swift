import AppKit
import Foundation
import UniformTypeIdentifiers

/// Finder Quick Action (`com.apple.services`, no UI, see `Info.plist`).
/// Reads the file URLs Finder handed us, routes by the first item's type
/// (default routing per the feature spec: image -> Compress Images, movie ->
/// Compress Videos, font -> Font Convert; a mixed selection keeps only the
/// files matching that first type, the rest are discarded), and hands off to
/// the host app via `nimbus://open` -- this extension runs sandboxed and
/// can't reach Nimbus's own state directly, and never runs the tool itself.
final class FinderActionHandler: NSObject, NSExtensionRequestHandling {
    private static let toolsByType: [UTType: String] = [
        .image: "to-webp",
        .movie: "to-webm",
        .font: "font-convert",
    ]

    func beginRequest(with context: NSExtensionContext) {
        let providers = context.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        loadFileURLs(from: providers) { [weak self] urls in
            defer { context.completeRequest(returningItems: nil, completionHandler: nil) }
            guard let self, let first = urls.first, let tool = self.tool(for: first) else { return }

            var components = URLComponents()
            components.scheme = "nimbus"
            components.host = "open"
            var query = [URLQueryItem(name: "tool", value: tool)]
            for url in urls where self.tool(for: url) == tool {
                query.append(URLQueryItem(name: "file", value: url.path))
            }
            components.queryItems = query
            guard let deepLink = components.url else { return }
            NSWorkspace.shared.open(deepLink)
        }
    }

    private func tool(for url: URL) -> String? {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return nil }
        return Self.toolsByType.first { type.conforms(to: $0.key) }?.value
    }

    /// Finder attaches each selected file as a `public.file-url` item
    /// provider; `loadItem` is async and callback-based even for a value
    /// already in hand, so every provider's load is awaited before routing.
    private func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let typeIdentifier = UTType.fileURL.identifier
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL? = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? item as? URL
                guard let url else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}
