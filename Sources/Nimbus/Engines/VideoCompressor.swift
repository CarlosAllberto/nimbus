import AVFoundation
import Foundation

/// Port of `Sidecar/tools/to-webm.mjs`: always WebM (VP9 + Opus). macOS has no
/// WebM encoder, so this runs the LGPL-only static ffmpeg that
/// `Tools/build-ffmpeg.sh` builds into `Resources/ffmpeg`.
/// `low` is CRF 28, `high` is CRF 38 capped at 720p, `lossless` is VP9 lossless.
enum VideoCompressor {
    typealias Level = CompressionLevel

    /// `progress` gets 0...1 on an arbitrary thread, as ffmpeg reports it.
    static func run(
        input: URL, level: Level = .low,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        try EngineIO.checkSize(input, limit: EngineIO.maxVideoBytes, noun: FileAcceptance.video.noun)

        // Content check: no playable video track means it isn't a video,
        // whatever the extension says.
        let asset = AVURLAsset(url: input)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
            throw EngineError.unsupportedFile
        }
        let seconds = (try? await asset.load(.duration).seconds) ?? 0

        guard let ffmpeg = ffmpegURL else {
            throw EngineError.encodingFailed(String(localized: "The video encoder is missing from this build. Run Tools/build-ffmpeg.sh.", bundle: .l10n))
        }
        let destination = EngineIO.uniqueURL(for: input, ext: "webm")
        let job = FFmpegJob(
            executable: ffmpeg,
            arguments: arguments(input: input, output: destination, level: level),
            duration: seconds, progress: progress)
        do {
            try await job.run()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        progress?(1)
        return destination
    }

    private static var ffmpegURL: URL? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: "ffmpeg", withExtension: nil)
            ?? bundle.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "Resources")
    }

    private static func arguments(input: URL, output: URL, level: Level) -> [String] {
        var args = [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-progress", "pipe:1", "-nostats", "-y",
            "-i", input.path,
            // First video track, first audio track if there is one.
            "-map", "0:v:0", "-map", "0:a:0?",
            "-c:v", "libvpx-vp9", "-row-mt", "1", "-deadline", "good", "-cpu-used", "3",
            "-c:a", "libopus",
        ]
        switch level {
        case .low:
            args += ["-crf", "28", "-b:v", "0", "-pix_fmt", "yuv420p", "-b:a", "96k"]
        case .high:
            // Never upscales: min() keeps smaller sources as they are.
            args += ["-crf", "38", "-b:v", "0", "-pix_fmt", "yuv420p", "-b:a", "64k",
                     "-vf", "scale=-2:min(720\\,ih)"]
        case .lossless:
            args += ["-lossless", "1", "-b:a", "96k"]
        }
        return args + ["-f", "webm", output.path]
    }
}

/// One ffmpeg run: progress from `-progress pipe:1` against the known
/// duration, stderr kept for the error message, task cancellation terminates
/// the process.
private final class FFmpegJob: @unchecked Sendable {
    private let process = Process()
    private let duration: Double
    private let progress: (@Sendable (Double) -> Void)?
    private let lock = NSLock()
    private var cancelled = false
    private var stderrTail = Data()

    init(executable: URL, arguments: [String], duration: Double, progress: (@Sendable (Double) -> Void)?) {
        process.executableURL = executable
        process.arguments = arguments
        self.duration = duration
        self.progress = progress
    }

    func run() async throws {
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        out.fileHandleForReading.readabilityHandler = { [self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            // `out_time_us` is the encoded position in microseconds.
            guard duration > 0, let line = text.split(separator: "\n").last(where: { $0.hasPrefix("out_time_us=") }),
                  let micros = Double(line.dropFirst("out_time_us=".count))
            else { return }
            progress?(min(max(micros / 1_000_000 / duration, 0), 0.99))
        }
        err.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            lock.withLock { stderrTail = (stderrTail + data).suffix(2000) }
        }
        defer {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { [self] process in
                    if lock.withLock({ cancelled }) {
                        continuation.resume(throwing: CancellationError())
                    } else if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let message = lock.withLock { String(decoding: stderrTail, as: UTF8.self) }
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: EngineError.encodingFailed(
                            message.isEmpty ? String(localized: "Video encoding failed.", bundle: .l10n) : message))
                    }
                }
                do {
                    // Holding the lock across launch keeps a cancel from landing
                    // between "not started" and "running".
                    try lock.withLock {
                        if cancelled { throw CancellationError() }
                        try process.run()
                    }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            lock.withLock {
                cancelled = true
                if process.isRunning { process.terminate() }
            }
        }
    }
}
