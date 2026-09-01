import Foundation
import Security

enum SidecarError: Error, LocalizedError {
    case nodeNotFound
    case scriptNotFound
    case launchFailed(String)
    case handshakeTimedOut
    case terminatedDuringHandshake(String)

    var errorDescription: String? {
        switch self {
        case .nodeNotFound:
            "Node.js is required to run this tool right now, but wasn't found on this Mac. Install Node (for example via Homebrew) and try again."
        case .scriptNotFound:
            "Nimbus couldn't find its sidecar script (Sidecar/server.mjs)."
        case let .launchFailed(reason):
            "Couldn't start the Nimbus sidecar: \(reason)"
        case .handshakeTimedOut:
            "The Nimbus sidecar didn't respond in time."
        case let .terminatedDuringHandshake(reason):
            "The Nimbus sidecar stopped unexpectedly while starting: \(reason)"
        }
    }
}

/// Launches the Node sidecar on demand, reads its handshake line to learn the
/// port it bound, and holds the per-run secret used to authenticate requests
/// to it. One shared instance owns at most one running process; `swift
/// build`/CI never exercises this — it only runs when a tool button is
/// actually pressed.
@MainActor
final class SidecarProcess {
    struct Endpoint {
        let baseURL: URL
        let secret: String
    }

    static let shared = SidecarProcess()

    private var process: Process?
    private var stdinPipe: Pipe?
    private var endpoint: Endpoint?
    private var startTask: Task<Endpoint, Error>?

    private init() {}

    /// Returns the running sidecar's endpoint, starting it first if needed.
    /// Concurrent callers awaiting a startup already in flight share it
    /// rather than racing to launch two sidecars.
    func ensureRunning() async throws -> Endpoint {
        if let endpoint, let process, process.isRunning {
            return endpoint
        }
        if let startTask {
            return try await startTask.value
        }

        let task = Task { try await self.start() }
        startTask = task
        defer { startTask = nil }
        let endpoint = try await task.value
        self.endpoint = endpoint
        return endpoint
    }

    /// Closing stdin — not `terminate()` — is the documented contract: the
    /// sidecar watches for its parent going away by watching its stdin close,
    /// which is also what keeps it from being orphaned if Nimbus is killed
    /// outright rather than quit normally.
    func shutdown() {
        guard process != nil else { return }
        process = nil
        endpoint = nil
        try? stdinPipe?.fileHandleForWriting.close()
        stdinPipe = nil
    }

    private func start() async throws -> Endpoint {
        let nodePath = try Self.locateNode()
        let scriptURL = try Self.locateSidecarScript()
        let secret = Self.generateSecret()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [scriptURL.path]

        var environment = ProcessInfo.processInfo.environment
        // Never in `arguments`: argv is visible to every process on the
        // machine via `ps`; the environment of a child process is not.
        environment["NIMBUS_SIDECAR_SECRET"] = secret
        // Absent or empty means the env var is not set at all, which is the
        // correct "no key configured" state — the sidecar route checks
        // `process.env.X?.trim()` and answers 503 exactly like the Next route
        // did when the key was missing on the server.
        if let geminiKey = try? KeychainSecretStore(account: NimbusSecretAccount.geminiAPIKey).read(), !geminiKey.isEmpty {
            environment["GEMINI_API_KEY"] = geminiKey
        }
        if let pageSpeedKey = try? KeychainSecretStore(account: NimbusSecretAccount.pageSpeedAPIKey).read(), !pageSpeedKey.isEmpty {
            environment["GOOGLE_PAGESPEED_API_KEY"] = pageSpeedKey
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardInput = stdinPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw SidecarError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinPipe = stdinPipe

        do {
            let port = try await Self.readHandshake(from: stdoutPipe, process: process)
            return Endpoint(baseURL: URL(string: "http://127.0.0.1:\(port)")!, secret: secret)
        } catch {
            self.process = nil
            self.stdinPipe = nil
            process.terminate()
            throw error
        }
    }

    /// Reads stdout line by line until it sees `NIMBUS_SIDECAR_READY
    /// {"port":N}`, or times out. A timeout is required, not optional: if the
    /// sidecar never prints that line, the caller would otherwise hang
    /// forever and the UI along with it.
    /// `nonisolated`: its task-group children run off the main actor by
    /// default, and this function and `parseHandshake` below touch nothing
    /// but their own parameters, so there is no reason to hop back.
    private nonisolated static func readHandshake(from pipe: Pipe, process: Process) async throws -> Int {
        try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask {
                var line = Data()
                for try await byte in pipe.fileHandleForReading.bytes {
                    if byte == UInt8(ascii: "\n") {
                        if let port = parseHandshake(line) { return port }
                        line.removeAll(keepingCapacity: true)
                    } else {
                        line.append(byte)
                    }
                }
                throw SidecarError.terminatedDuringHandshake(
                    process.isRunning ? "output closed unexpectedly" : "process exited"
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                throw SidecarError.handshakeTimedOut
            }
            defer { group.cancelAll() }
            guard let port = try await group.next() else { throw SidecarError.handshakeTimedOut }
            return port
        }
    }

    private nonisolated static func parseHandshake(_ lineData: Data) -> Int? {
        let prefix = "NIMBUS_SIDECAR_READY "
        guard let line = String(data: lineData, encoding: .utf8), line.hasPrefix(prefix) else { return nil }
        let payload = Data(line.dropFirst(prefix.count).utf8)
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        return object["port"] as? Int
    }

    /// `/opt/homebrew/bin/node` is where Node lives on this machine, but
    /// that's an Apple Silicon Homebrew detail, not a promise — Intel
    /// Homebrew, a system install, or a version manager all put it somewhere
    /// else, so the well-known locations and `PATH` are all checked before
    /// giving up.
    private static func locateNode() throws -> String {
        let fileManager = FileManager.default
        let wellKnownPaths = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        for path in wellKnownPaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }

        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
        for directory in pathEntries {
            let candidate = "\(directory)/node"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw SidecarError.nodeNotFound
    }

    /// The packaged app carries `Sidecar/` as a copied resource for release
    /// builds; a debug run from Xcode (or `swift build`, which produces no
    /// bundle at all) needs the source tree itself, found relative to this
    /// file rather than to a working directory that varies by how the app
    /// was launched.
    private static func locateSidecarScript() throws -> URL {
        if let bundled = Bundle.main.url(forResource: "server", withExtension: "mjs", subdirectory: "Sidecar") {
            return bundled
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Sources/Nimbus
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // repo root
        let devScript = repoRoot.appendingPathComponent("Sidecar/server.mjs")
        if FileManager.default.fileExists(atPath: devScript.path) {
            return devScript
        }

        throw SidecarError.scriptNotFound
    }

    private static func generateSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed unexpectedly")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
