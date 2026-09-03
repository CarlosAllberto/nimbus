import SwiftUI

enum ToolGroup: String, CaseIterable, Identifiable {
    case web, studio, code, tools

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .web: "globe"
        case .studio: "wand.and.stars"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

struct NimbusTool: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let icon: String
    let group: ToolGroup
}

enum ToolCatalog {
    static let tools: [NimbusTool] = [
        NimbusTool(id: "to-webp", name: "Compress Images", summary: "Shrink images, or convert them to WebP.", icon: "photo", group: .web),
        NimbusTool(id: "copy-generator", name: "Copy Generator", summary: "Generate polished copy.", icon: "doc.on.clipboard", group: .web),
        NimbusTool(id: "ico", name: "Favicon Generator", summary: "Turn an image into a browser favicon (.ico).", icon: "app.badge", group: .web),
        NimbusTool(id: "to-webm", name: "Compress Videos", summary: "Shrink a video by converting it to WebM.", icon: "film", group: .web),
        NimbusTool(id: "whois-scan", name: "WHOIS Scan", summary: "Inspect domain registration details.", icon: "magnifyingglass", group: .web),
        NimbusTool(id: "dns-check", name: "DNS Check", summary: "Check DNS records for a domain.", icon: "network", group: .web),
        NimbusTool(id: "site-speed", name: "Site Speed", summary: "Review website performance.", icon: "gauge.with.dots.needle.67percent", group: .web),
        NimbusTool(id: "wordpress-inspector", name: "WordPress Inspector", summary: "Inspect a WordPress site.", icon: "shippingbox", group: .web),
        NimbusTool(id: "policy-generator", name: "Policy Generator", summary: "Create a website policy.", icon: "doc.text", group: .web),
        NimbusTool(id: "responsive-font-clamp", name: "Responsive Font Clamp", summary: "Build responsive font sizing.", icon: "textformat.size", group: .web),

        NimbusTool(id: "device-wrapper", name: "Device Wrapper", summary: "Place an image inside a device frame.", icon: "iphone", group: .studio),
        NimbusTool(id: "trim-image", name: "Trim Image", summary: "Trim an image to its content.", icon: "crop", group: .studio),
        NimbusTool(id: "convert", name: "Convert", summary: "Convert between common file formats.", icon: "arrow.2.squarepath", group: .studio),
        NimbusTool(id: "resize", name: "Resize Image", summary: "Resize an image.", icon: "arrow.up.left.and.arrow.down.right", group: .studio),
        NimbusTool(id: "resize-video", name: "Resize Video", summary: "Resize a video for a new frame.", icon: "film", group: .studio),
        NimbusTool(id: "upscale", name: "Upscale Image", summary: "Enlarge an image 2x with lanczos3 interpolation.", icon: "plus.magnifyingglass", group: .studio),
        NimbusTool(id: "to-mp3", name: "MP4 to MP3", summary: "Extract the audio track from a video as MP3.", icon: "waveform", group: .studio),

        NimbusTool(id: "html-minify", name: "HTML Minify", summary: "Minify or unminify HTML.", icon: "chevron.left.forwardslash.chevron.right", group: .code),
        NimbusTool(id: "js-minify", name: "JavaScript Minify", summary: "Minify or unminify JavaScript.", icon: "curlybraces", group: .code),
        // Hidden for now, not ready — re-add once it's in better shape.
        // NimbusTool(id: "json-creator", name: "JSON Creator", summary: "Create and format JSON.", icon: "curlybraces", group: .code),

        NimbusTool(id: "password-generator", name: "Password Generator", summary: "Generate a secure password locally.", icon: "key", group: .tools),
        NimbusTool(id: "color-convert", name: "Color Convert", summary: "Convert between color formats.", icon: "paintpalette", group: .tools),
        NimbusTool(id: "palette-from-image", name: "Palette From Image", summary: "Extract a color palette from an image.", icon: "eyedropper.halffull", group: .tools),
        NimbusTool(id: "contrast-check", name: "Contrast Check", summary: "Check accessible color contrast.", icon: "circle.lefthalf.filled", group: .tools),
        NimbusTool(id: "wa-link", name: "WhatsApp Link", summary: "Create a WhatsApp link.", icon: "message", group: .tools),
        NimbusTool(id: "contract-pdf", name: "Contract PDF", summary: "Create a contract PDF.", icon: "doc.richtext", group: .tools),
        NimbusTool(id: "qrcode", name: "QR Code", summary: "Create a QR code.", icon: "qrcode", group: .tools),
        NimbusTool(id: "font-convert", name: "Font Convert", summary: "Convert a font file.", icon: "textformat", group: .tools),
        NimbusTool(id: "pick-color", name: "Pick Color", summary: "Sample any color on screen.", icon: "eyedropper", group: .tools),
    ]
}

enum NimbusTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
