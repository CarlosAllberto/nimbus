import Foundation

struct NimbusTool: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let icon: String
}

/// The six Quick Drop tools, in well order. Names are two words in every
/// language: the well label puts one word per line.
enum ToolCatalog {
    static let tools: [NimbusTool] = [
        NimbusTool(id: "to-webp", name: String(localized: "Compress Images", bundle: .l10n), summary: String(localized: "Shrink images, or convert them to WebP.", bundle: .l10n), icon: "photo"),
        NimbusTool(id: "to-webm", name: String(localized: "Compress Videos", bundle: .l10n), summary: String(localized: "Shrink a video, saved as WebM.", bundle: .l10n), icon: "film"),
        NimbusTool(id: "ico", name: String(localized: "Favicon Generator", bundle: .l10n), summary: String(localized: "Turn an image into a browser favicon (.ico).", bundle: .l10n), icon: "app.badge"),
        NimbusTool(id: "trim-image", name: String(localized: "Auto Crop", bundle: .l10n), summary: String(localized: "Crop an image to its content automatically.", bundle: .l10n), icon: "crop"),
        NimbusTool(id: "convert", name: String(localized: "Image Converter", bundle: .l10n), summary: String(localized: "Convert between common image formats.", bundle: .l10n), icon: "arrow.2.squarepath"),
        NimbusTool(id: "video-convert", name: String(localized: "Video Converter", bundle: .l10n), summary: String(localized: "Convert a video to another format.", bundle: .l10n), icon: "play.rectangle"),
    ]
}
