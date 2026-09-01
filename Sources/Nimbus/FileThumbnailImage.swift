import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Renders a QuickLook-generated thumbnail for a file URL, falling back to a system
/// symbol when QuickLook can't produce one. Shared by `FileToolView`'s full-size
/// previews and `CompactFileField`'s compact ones so there is one thumbnail pipeline.
struct FileThumbnailImage: View {
    let url: URL
    let size: CGFloat
    let fallbackSymbol: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            image = await Self.loadThumbnail(for: url, size: size, fallbackSymbol: fallbackSymbol)
        }
    }

    static func loadThumbnail(for url: URL, size: CGFloat, fallbackSymbol: String) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size * 2, height: size * 2),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        do {
            return try await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request)
                .nsImage
        } catch {
            return NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil)
        }
    }
}
