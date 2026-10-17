import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Ports `Sidecar/tools/to-webp.mjs`: EXIF-rotate, fit to 1920 px wide
/// (never enlarging), then encode as WebP or, with `convertToWebP` off, in the
/// source format (JPEG, PNG, HEIC).
enum ImageCompressor {
    typealias Level = CompressionLevel

    static let maxWidth = 1920
    /// `high` aims for this share of the original size, as the sidecar did.
    private static let targetFactor = 0.42
    private static let searchRange = 26...72

    static func run(input: URL, level: Level = .low, convertToWebP: Bool = true) async throws -> URL {
        let source = try EngineIO.imageSource(input)
        let size = EngineIO.pixelSize(source)
        let image = try EngineIO.decodeOriented(source, maxWidth: maxWidth)
        try Task.checkCancellation()

        // The sidecar sized the target from the resized buffer; the pixel
        // ratio is the closest stand-in without encoding it first.
        let ratio = Double(image.width * image.height) / Double(max(1, size.width * size.height))
        let target = Double(EngineIO.fileSize(input)) * min(1, ratio) * targetFactor

        let sourceType = EngineIO.imageType(source)
        let (data, ext): (Data, String)
        if convertToWebP || sourceType?.conforms(to: .webP) == true {
            (data, ext) = (try webP(image, level, target), "webp")
        } else if sourceType?.conforms(to: .png) == true {
            (data, ext) = (try EngineIO.encode(image, as: .png), "png")
        } else if sourceType?.conforms(to: .heic) == true || sourceType?.conforms(to: .heif) == true {
            (data, ext) = try heic(image, level, target)
        } else {
            (data, ext) = (try jpeg(image, level, target), "jpg")
        }
        try Task.checkCancellation()
        return try EngineIO.write(data, for: input, ext: ext)
    }

    // MARK: - Encoders

    private static func webP(_ image: CGImage, _ level: Level, _ target: Double) throws -> Data {
        switch level {
        case .lossless:
            return try WebPCodec.encode(image, lossless: true)
        case .low:
            return try WebPCodec.encode(image, lossless: false, quality: 90, alphaQuality: 80)
        case .high:
            return try searchQuality(target: target) {
                try WebPCodec.encode(image, lossless: false, quality: Float($0), alphaQuality: 60)
            }
        }
    }

    private static func jpeg(_ image: CGImage, _ level: Level, _ target: Double) throws -> Data {
        switch level {
        case .lossless: return try EngineIO.encode(image, as: .jpeg, quality: 1)
        case .low: return try EngineIO.encode(image, as: .jpeg, quality: 0.9)
        case .high:
            return try searchQuality(target: target) {
                try EngineIO.encode(image, as: .jpeg, quality: Double($0) / 100)
            }
        }
    }

    /// Like the sidecar, a HEIC the machine can't write falls back to JPEG.
    private static func heic(_ image: CGImage, _ level: Level, _ target: Double) throws -> (Data, String) {
        let quality = level == .lossless ? 1.0 : level == .low ? 0.9 : 0.65
        if let data = try? EngineIO.encode(image, as: .heic, quality: quality) { return (data, "heic") }
        return (try jpeg(image, level, target), "jpg")
    }

    /// Binary search over quality, keeping the best encode that fits `target`.
    private static func searchQuality(target: Double, encode: (Int) throws -> Data) throws -> Data {
        var low = searchRange.lowerBound, high = searchRange.upperBound
        var best: Data?
        while low <= high {
            let quality = (low + high + 1) / 2
            let candidate = try encode(quality)
            if Double(candidate.count) > target {
                high = quality - 1
            } else {
                best = candidate
                low = quality + 1
            }
        }
        // Nothing fit: the floor quality is the smallest file on offer. (The
        // sidecar returned the untouched input here for WebP, a bug.)
        return try best ?? encode(searchRange.lowerBound)
    }
}
