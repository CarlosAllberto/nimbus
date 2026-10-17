import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Ports `Sidecar/tools/trim-image.mjs`: like sharp's `.trim()`, the top-left
/// pixel is the background and anything within `threshold` of it on every
/// channel counts as border. Output is PNG.
enum ImageTrimmer {
    static let threshold = 10

    static func run(input: URL) async throws -> URL {
        let image = try EngineIO.decode(try EngineIO.imageSource(input))
        let pixels = try EngineIO.rgba(image, premultiplied: true)
        try Task.checkCancellation()

        let width = image.width, height = image.height
        let background = Array(pixels[0..<4])
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let isBorder = (0..<4).allSatisfy { abs(Int(pixels[i + $0]) - Int(background[$0])) <= threshold }
                if !isBorder {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }

        // A uniform image has nothing to keep; hand it back whole.
        let rect = maxX < 0
            ? CGRect(x: 0, y: 0, width: width, height: height)
            : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let trimmed = image.cropping(to: rect) else {
            throw EngineError.encodingFailed(String(localized: "Could not crop the image.", bundle: .l10n))
        }
        return try EngineIO.write(try EngineIO.encode(trimmed, as: .png), for: input, ext: "png")
    }
}
