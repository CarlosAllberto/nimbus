import AVFoundation
import Foundation

/// Re-encodes a video to MP4, MOV or WebM. MP4 and MOV go through
/// AVFoundation (H.264, highest quality preset); WebM is `VideoCompressor`'s
/// ffmpeg path at its low level (CRF 28). Always re-encodes, even when the
/// input already has that format; the output never overwrites anything.
enum VideoConverter {
    enum Format: String, Sendable, CaseIterable {
        case mp4, mov, webm

        var fileType: AVFileType? {
            switch self {
            case .mp4: .mp4
            case .mov: .mov
            case .webm: nil
            }
        }
    }

    static func run(input: URL, format: Format) async throws -> URL {
        guard let fileType = format.fileType else {
            return try await VideoCompressor.run(input: input, level: .low)
        }
        try EngineIO.checkSize(input, limit: EngineIO.maxVideoBytes, noun: FileAcceptance.video.noun)

        // Content check: no playable video track means it isn't a video,
        // whatever the extension says.
        let asset = AVURLAsset(url: input)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
            throw EngineError.unsupportedFile
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
              session.supportedFileTypes.contains(fileType)
        else {
            throw EngineError.encodingFailed(String(localized: "This video can't be converted to that format.", bundle: .l10n))
        }
        let destination = EngineIO.uniqueURL(for: input, ext: format.rawValue)
        session.outputURL = destination
        session.outputFileType = fileType

        let export = ExportBox(session)
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    export.session.exportAsynchronously {
                        switch export.session.status {
                        case .completed: continuation.resume()
                        case .cancelled: continuation.resume(throwing: CancellationError())
                        default:
                            continuation.resume(throwing: export.session.error
                                ?? EngineError.encodingFailed(String(localized: "Video encoding failed.", bundle: .l10n)))
                        }
                    }
                }
            } onCancel: {
                export.session.cancelExport()
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }
}

/// `AVAssetExportSession` isn't `Sendable`, but it is only touched through
/// its own thread-safe export calls here.
private final class ExportBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
