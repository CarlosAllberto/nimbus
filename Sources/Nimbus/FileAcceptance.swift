import Foundation
import UniformTypeIdentifiers

enum FileAcceptance: Equatable {
    case image
    case video
    case font
    case document

    var allowedContentTypes: [UTType] {
        switch self {
        case .image: [.image]
        case .video: [.movie]
        case .font:
            ["ttf", "otf", "woff", "woff2", "eot"].compactMap {
                UTType(filenameExtension: $0)
            }
        case .document:
            [.plainText, .pdf] + (UTType(filenameExtension: "docx").map { [$0] } ?? [])
        }
    }

    /// Mirrors the limits in `Engines/EngineSupport.swift`. Checked here as well
    /// so an oversized file fails the moment it is picked, before an engine
    /// is started on it.
    var maximumBytes: Int {
        switch self {
        case .image: 250 * 1024 * 1024
        case .video: 1024 * 1024 * 1024
        case .font: 100 * 1024 * 1024
        case .document: 100 * 1024 * 1024
        }
    }

    var maximumSizeMessage: String {
        let megabytes = maximumBytes / (1024 * 1024)
        return String(localized: "This \(noun) is larger than the \(megabytes) MB limit.", bundle: .l10n)
    }

    var noun: String {
        switch self {
        case .image: String(localized: "image", bundle: .l10n)
        case .video: String(localized: "video", bundle: .l10n)
        case .font: String(localized: "font", bundle: .l10n)
        case .document: String(localized: "document", bundle: .l10n)
        }
    }

    var symbol: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .font: "textformat"
        case .document: "doc.text"
        }
    }

    func accepts(_ url: URL) -> Bool {
        let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        return accepts(contentType: contentType, fileExtension: url.pathExtension)
    }

    func accepts(contentType: UTType?, fileExtension: String) -> Bool {
        switch self {
        case .image:
            return contentType?.conforms(to: .image) == true
        case .video:
            return contentType?.conforms(to: .movie) == true
        case .font:
            return ["ttf", "otf", "woff", "woff2", "eot"]
                .contains(fileExtension.lowercased())
        case .document:
            return ["txt", "docx", "pdf"]
                .contains(fileExtension.lowercased())
        }
    }
}
