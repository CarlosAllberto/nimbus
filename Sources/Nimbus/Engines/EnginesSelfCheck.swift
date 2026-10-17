import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Runs each engine once on generated input and throws on the first broken
/// expectation. Returns one line per passed check. Not wired into the app;
/// call it from a scratch harness or a debugger.
func enginesSelfCheck() async throws -> [String] {
    struct Failed: Error, CustomStringConvertible { let description: String }
    func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failed(description: message) }
    }
    func size(_ url: URL) -> Int { EngineIO.fileSize(url) }
    func dimensions(_ url: URL) throws -> (Int, Int) {
        let s = try EngineIO.pixelSize(EngineIO.imageSource(url))
        return (s.width, s.height)
    }

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nimbus-engines-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var report: [String] = []

    // A noisy gradient with a 40 px transparent border: photo-like enough that
    // lossy WebP beats PNG, and something for the trimmer to remove.
    let context = try EngineIO.makeContext(width: 400, height: 300)
    var seed: UInt64 = 42
    for y in 0..<220 {
        for x in 0..<320 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = CGFloat(seed >> 59) / 255
            context.setFillColor(CGColor(red: CGFloat(x) / 320 + noise, green: CGFloat(y) / 220, blue: 0.5 - noise, alpha: 1))
            context.fill(CGRect(x: 40 + x, y: 40 + y, width: 1, height: 1))
        }
    }
    let png = folder.appendingPathComponent("sample.png")
    try EngineIO.encode(try { guard let i = context.makeImage() else { throw Failed(description: "no image") }; return i }(), as: .png).write(to: png)

    // PNG -> WebP is smaller (high), and lossless keeps the dimensions.
    let webp = try await ImageCompressor.run(input: png, level: .high)
    try expect(size(webp) < size(png), "webp (\(size(webp)) B) not smaller than png (\(size(png)) B)")
    try expect(try dimensions(webp) == dimensions(png), "webp doesn't decode at the source size")
    let lossless = try await ImageCompressor.run(input: png, level: .lossless)
    try expect(try dimensions(lossless) == dimensions(png), "lossless webp changed dimensions")
    report.append("PNG->WebP: \(size(png)) B -> \(size(webp)) B, lossless \(try dimensions(lossless))")

    let converted = try await ImageConverter.run(input: png, format: .jpg)
    try expect(converted.pathExtension == "jpg" && size(converted) > 0, "convert to jpg failed")
    report.append("Convert: \(converted.lastPathComponent)")

    // Trim removes the 40 px border: 400x300 -> 320x220.
    let trimmed = try await ImageTrimmer.run(input: png)
    let (tw, th) = try dimensions(trimmed)
    try expect(tw < 400 && th < 300 && tw >= 320 && th >= 220, "trim gave \(tw)x\(th)")
    report.append("Trim: 400x300 -> \(tw)x\(th)")

    // ICO header: reserved 0, type 1, one image, 32x32, PNG payload at offset 22.
    let zip = try await FaviconMaker.run(input: png, safeMargin: true)
    try expect(try Data(contentsOf: zip).prefix(2) == Data("PK".utf8), "favicon archive isn't a zip")
    let ico = FaviconMaker.icoData(wrapping: try FaviconMaker.pngIcon(try EngineIO.decode(EngineIO.imageSource(png)), size: 32, margin: 0))
    try expect(Array(ico.prefix(8)) == [0, 0, 1, 0, 1, 0, 32, 32], "bad ICO header")
    try expect(Array(ico[22..<26]) == [0x89, 0x50, 0x4E, 0x47], "ICO payload isn't a PNG")
    report.append("Favicons: ICO header valid, \(zip.lastPathComponent)")

    // A 2 s 1280x720 clip at a deliberately fat bitrate compresses to WebM.
    let clip = folder.appendingPathComponent("clip.mov")
    try await writeClip(to: clip)
    let webm = try await VideoCompressor.run(input: clip, level: .high)
    try expect(webm.pathExtension == "webm" && size(webm) < size(clip), "webm \(size(webm)) B vs source \(size(clip)) B")
    // EBML magic: the container really is Matroska/WebM, not renamed MP4.
    try expect(try Data(contentsOf: webm).prefix(4) == Data([0x1A, 0x45, 0xDF, 0xA3]), "webm has no EBML header")
    report.append("Video: \(size(clip)) B -> \(size(webm)) B webm")

    // Video Converter: every format yields a non-empty file; mp4/mov must
    // reopen in AVFoundation with a video track.
    for format in VideoConverter.Format.allCases {
        let out = try await VideoConverter.run(input: clip, format: format)
        try expect(out.pathExtension == format.rawValue && size(out) > 0, "video convert to \(format.rawValue) failed")
        if format != .webm {
            let tracks = try await AVURLAsset(url: out).loadTracks(withMediaType: .video)
            try expect(!tracks.isEmpty, "\(format.rawValue) output has no video track")
        }
        report.append("Video convert: \(format.rawValue) \(size(out)) B")
    }

    // Boundary: a text file with an image extension is rejected.
    let fake = folder.appendingPathComponent("fake.png")
    try Data("not an image".utf8).write(to: fake)
    do { _ = try await ImageCompressor.run(input: fake); throw Failed(description: "fake image accepted") }
    catch EngineError.unsupportedFile { report.append("Validation: fake image rejected") }

    return report
}

private func writeClip(to url: URL) async throws {
    let (width, height, frames) = (1280, 720, 60)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 20_000_000],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<frames {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { throw EngineError.encodingFailed("no pixel buffer") }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<height {
                for x in 0..<(width * 4) { bytes[y * rowBytes + x] = UInt8(truncatingIfNeeded: x &* 7 &+ y &* 3 &+ frame &* 11 &+ (x >> 6)) }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
    }
    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed { throw writer.error ?? EngineError.encodingFailed("clip write failed") }
}
