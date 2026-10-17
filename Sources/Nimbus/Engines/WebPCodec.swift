import CoreGraphics
import Foundation
import libwebp

/// Thin wrapper over libwebp's advanced encoder (`method 6`, sharp YUV: what
/// sharp's `effort: 6, smartSubsample: true` selects).
enum WebPCodec {
    static func encode(
        _ image: CGImage, lossless: Bool, quality: Float = 75, alphaQuality: Int32 = 100, method: Int32 = 6
    ) throws -> Data {
        guard image.width <= 16383, image.height <= 16383 else {
            throw EngineError.encodingFailed(String(localized: "Image is too large for WebP (16383 px per side).", bundle: .l10n))
        }
        let pixels = try EngineIO.rgba(image, premultiplied: false)

        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else { throw EngineError.encodingFailed(String(localized: "libwebp failed to initialise.", bundle: .l10n)) }
        config.lossless = lossless ? 1 : 0
        config.exact = lossless ? 1 : 0
        config.quality = quality
        config.method = method
        config.alpha_quality = alphaQuality
        config.use_sharp_yuv = 1
        guard WebPValidateConfig(&config) != 0 else { throw EngineError.encodingFailed(String(localized: "Invalid WebP settings.", bundle: .l10n)) }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw EngineError.encodingFailed(String(localized: "libwebp failed to initialise.", bundle: .l10n)) }
        defer { WebPPictureFree(&picture) }
        picture.use_argb = lossless ? 1 : 0
        picture.width = Int32(image.width)
        picture.height = Int32(image.height)
        let imported = pixels.withUnsafeBufferPointer {
            WebPPictureImportRGBA(&picture, $0.baseAddress, Int32(image.width * 4))
        }
        guard imported != 0 else { throw EngineError.encodingFailed(String(localized: "Could not load pixels into libwebp.", bundle: .l10n)) }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        picture.writer = WebPMemoryWrite
        let ok = withUnsafeMutablePointer(to: &writer) { pointer in
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture)
        }
        guard ok != 0, let bytes = writer.mem else { throw EngineError.encodingFailed(String(localized: "WebP encoding failed.", bundle: .l10n)) }
        return Data(bytes: bytes, count: writer.size)
    }
}
