import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared by the image and video engines. Maps the sidecar's `perda` /
/// `lustroso` / `sem-perdas` presets: `low` compression keeps quality,
/// `high` compression shrinks the file, `lossless` keeps every pixel.
enum CompressionLevel: String, Sendable, CaseIterable {
    case low
    case high
    case lossless
}

enum EngineError: LocalizedError {
    case unsupportedFile
    case tooLarge(noun: String, megabytes: Int)
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            String(localized: "This file isn't supported.", bundle: .l10n)
        case .tooLarge(let noun, let megabytes):
            String(localized: "This \(noun) is larger than the \(megabytes) MB limit.", bundle: .l10n)
        case .encodingFailed(let reason):
            reason
        }
    }
}

/// Boundary checks and file helpers the engines share. Ports
/// `Sidecar/uploadLimits.mjs`, `verifyImage.mjs` and `verifyVideo.mjs`.
enum EngineIO {
    static let maxImageBytes = 250 * 1024 * 1024
    static let maxVideoBytes = 1024 * 1024 * 1024

    static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func checkSize(_ url: URL, limit: Int, noun: String) throws {
        if fileSize(url) > limit {
            throw EngineError.tooLarge(noun: noun, megabytes: limit / (1024 * 1024))
        }
    }

    /// Size limit, then content sniffing: ImageIO reads the magic bytes, never
    /// the extension, so a renamed text file is rejected.
    static func imageSource(_ url: URL) throws -> CGImageSource {
        try checkSize(url, limit: maxImageBytes, noun: FileAcceptance.image.noun)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source),
              UTType(identifier as String)?.conforms(to: .image) == true
        else { throw EngineError.unsupportedFile }
        return source
    }

    static func imageType(_ source: CGImageSource) -> UTType? {
        (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
    }

    /// Pixel size as stored, before any EXIF rotation.
    static func pixelSize(_ source: CGImageSource) -> (width: Int, height: Int, orientation: Int) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (
            properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
            properties?[kCGImagePropertyPixelHeight] as? Int ?? 0,
            properties?[kCGImagePropertyOrientation] as? Int ?? 1
        )
    }

    /// Raw pixels, no EXIF rotation (sharp's default).
    static func decode(_ source: CGImageSource) throws -> CGImage {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw EngineError.unsupportedFile
        }
        return image
    }

    /// Like sharp's `.rotate().resize({ width, withoutEnlargement, fit: 'inside' })`.
    static func decodeOriented(_ source: CGImageSource, maxWidth: Int) throws -> CGImage {
        let size = pixelSize(source)
        let displayWidth = (5...8).contains(size.orientation) ? size.height : size.width
        let longSide = max(size.width, size.height)
        let scale = displayWidth > maxWidth ? Double(maxWidth) / Double(displayWidth) : 1
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int((Double(longSide) * scale).rounded())),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw EngineError.unsupportedFile
        }
        return image
    }

    static func makeContext(width: Int, height: Int, alpha: CGImageAlphaInfo = .premultipliedLast) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: alpha.rawValue
              )
        else { throw EngineError.encodingFailed(String(localized: "Could not allocate an image buffer.", bundle: .l10n)) }
        return context
    }

    /// 8-bit RGBA, row 0 on top. WebP wants straight alpha; trimming is happy
    /// with premultiplied.
    static func rgba(_ image: CGImage, premultiplied: Bool) throws -> [UInt8] {
        let width = image.width, height = image.height
        let context = try makeContext(width: width, height: height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let base = context.data else { throw EngineError.encodingFailed(String(localized: "Could not read pixels.", bundle: .l10n)) }
        let rowBytes = context.bytesPerRow
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let source = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<(width * 4) { pixels[y * width * 4 + x] = source[y * rowBytes + x] }
        }
        if !premultiplied {
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let alpha = Int(pixels[i + 3])
                guard alpha != 0, alpha != 255 else { continue }
                for c in 0..<3 { pixels[i + c] = UInt8(min(255, (Int(pixels[i + c]) * 255 + alpha / 2) / alpha)) }
            }
        }
        return pixels
    }

    /// JPEG has no alpha; sharp flattens onto black, so do the same.
    static func flattenedOnBlack(_ image: CGImage) throws -> CGImage {
        let context = try makeContext(width: image.width, height: image.height, alpha: .noneSkipLast)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        guard let flat = context.makeImage() else { throw EngineError.encodingFailed(String(localized: "Could not flatten the image.", bundle: .l10n)) }
        return flat
    }

    /// `quality` is 0...1 and only applies to lossy types.
    static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw EngineError.encodingFailed(String(localized: "This Mac can't write \(type.preferredFilenameExtension ?? "?") files.", bundle: .l10n))
        }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, type == .jpeg ? try flattenedOnBlack(image) : image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EngineError.encodingFailed(String(localized: "Could not encode the image.", bundle: .l10n))
        }
        return data as Data
    }

    /// Every result lands in `~/Nimbus`, away from the originals: `name.ext`,
    /// then `name-2.ext`... — never over an existing file.
    static let outputDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Nimbus", isDirectory: true)

    static func uniqueURL(for input: URL, ext: String) -> URL {
        let directory = outputDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = input.deletingPathExtension().lastPathComponent
        var url = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)-\(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return url
    }

    static func write(_ data: Data, for input: URL, ext: String) throws -> URL {
        let url = uniqueURL(for: input, ext: ext)
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }
}
