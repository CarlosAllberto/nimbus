import Foundation
import UniformTypeIdentifiers

/// Ports `Sidecar/tools/convert.mjs`: re-encode to PNG, JPEG or WebP with
/// sharp's defaults (JPEG and WebP at quality 80).
enum ImageConverter {
    enum Format: String, Sendable, CaseIterable {
        case png, jpg, webp
    }

    static func run(input: URL, format: Format) async throws -> URL {
        let image = try EngineIO.decode(try EngineIO.imageSource(input))
        try Task.checkCancellation()
        let data: Data
        switch format {
        case .png: data = try EngineIO.encode(image, as: .png)
        case .jpg: data = try EngineIO.encode(image, as: .jpeg, quality: 0.8)
        case .webp: data = try WebPCodec.encode(image, lossless: false, quality: 80, method: 4)
        }
        return try EngineIO.write(data, for: input, ext: format.rawValue)
    }
}
