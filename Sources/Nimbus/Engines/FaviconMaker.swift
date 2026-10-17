import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Ports `Sidecar/tools/ico.mjs`: `favicon.ico` (one 32x32 PNG in an ICO
/// wrapper) plus the four PNG sizes, zipped into the Nimbus folder.
enum FaviconMaker {
    /// Margin per side, so rounded browser tabs don't clip the corners.
    static let safeMarginRatio = 0.12

    private static let outputs: [(name: String, size: Int)] = [
        ("favicon-16x16.png", 16),
        ("favicon-32x32.png", 32),
        ("apple-touch-icon.png", 180),
        ("android-chrome-192x192.png", 192),
        ("android-chrome-512x512.png", 512),
    ]

    static func run(input: URL, safeMargin: Bool = false) async throws -> URL {
        let image = try EngineIO.decode(try EngineIO.imageSource(input))
        let margin = safeMargin ? safeMarginRatio : 0

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("favicons", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        try icoData(wrapping: try pngIcon(image, size: 32, margin: margin))
            .write(to: folder.appendingPathComponent("favicon.ico"))
        for (name, size) in outputs {
            try Task.checkCancellation()
            try pngIcon(image, size: size, margin: margin).write(to: folder.appendingPathComponent(name))
        }
        return try zip(folder, for: input)
    }

    /// Fits the image inside the square, centred on a transparent canvas.
    static func pngIcon(_ image: CGImage, size: Int, margin: Double) throws -> Data {
        let inner = Double(max(1, Int((Double(size) * (1 - 2 * margin)).rounded())))
        let scale = inner / Double(max(image.width, image.height))
        let width = Double(image.width) * scale, height = Double(image.height) * scale
        let context = try EngineIO.makeContext(width: size, height: size)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(
            x: (Double(size) - width) / 2, y: (Double(size) - height) / 2, width: width, height: height
        ))
        guard let icon = context.makeImage() else { throw EngineError.encodingFailed(String(localized: "Could not draw the icon.", bundle: .l10n)) }
        return try EngineIO.encode(icon, as: .png)
    }

    /// A 22-byte ICONDIR + ICONDIRENTRY wrapping a single 32x32 PNG.
    static func icoData(wrapping png: Data) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
            withUnsafeBytes(of: value.littleEndian) { Array($0) }
        }
        var data = Data()
        data += le(UInt16(0))           // reserved
        data += le(UInt16(1))           // type: icon
        data += le(UInt16(1))           // image count
        data += [32, 32, 0, 0]          // width, height, palette colours, reserved
        data += le(UInt16(1))           // colour planes
        data += le(UInt16(32))          // bits per pixel
        data += le(UInt32(png.count))
        data += le(UInt32(22))          // offset of the image data
        return data + png
    }

    /// The system zips a coordinated read with `.forUploading`; no zip code
    /// of our own, and it works inside the sandbox.
    private static func zip(_ folder: URL, for input: URL) throws -> URL {
        let destination = EngineIO.uniqueURL(for: input, ext: "zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) {
            do { try FileManager.default.copyItem(at: $0, to: destination) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return destination
    }
}
