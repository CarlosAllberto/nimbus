import Darwin
import Dispatch
import Foundation

enum LoopbackAuthServerError: Error, Equatable, LocalizedError {
    case listenerFailed(String)
    case timedOut
    case cancelled
    case invalidCallback(String)

    var errorDescription: String? {
        switch self {
        case let .listenerFailed(detail):
            return "Could not start the local sign-in listener (\(detail)). Close any other Nimbus build and try again."
        case .timedOut:
            return "Sign-in timed out. Try again."
        case .cancelled:
            return "Sign-in was cancelled."
        case let .invalidCallback(reason):
            return reason
        }
    }
}

/// Single-callback loopback server for OAuth (RFC 8252). Binds 127.0.0.1 only,
/// never 0.0.0.0 — it is a private relay for the browser's redirect, not a
/// service. It lives for exactly one sign-in attempt: `AuthSession` starts one
/// before opening the browser and tears it down as soon as the attempt
/// resolves (success, provider error, timeout, or an explicit `stop()`).
///
/// Built on a plain POSIX socket rather than `NWListener`: on this macOS,
/// `NWListener` fails to start with `EINVAL` for *any* port (measured inside
/// the app — auto-assigned, 8123 and 53682 all failed) while a POSIX bind on
/// the same port in the same process succeeds. Because every listener failure
/// used to surface as "port already in use", that looked like a port conflict
/// when the port was in fact free.
@MainActor
final class LoopbackAuthServer {
    private let socketFD: Int32
    private var acceptSource: DispatchSourceRead?
    private var connectionSources: [DispatchSourceRead] = []
    private var continuation: CheckedContinuation<String, Error>?
    private var didResume = false

    private init(socketFD: Int32) {
        self.socketFD = socketFD
    }

    /// Throws `.listenerFailed` when the socket cannot be bound — the only
    /// place that needs to know why; callers just surface the message.
    static func start(port: UInt16, path: String) async throws -> LoopbackAuthServer {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw LoopbackAuthServerError.listenerFailed(Self.describe(errno))
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let reason = Self.describe(errno)
            close(fd)
            throw LoopbackAuthServerError.listenerFailed(reason)
        }
        guard Darwin.listen(fd, 1) == 0 else {
            let reason = Self.describe(errno)
            close(fd)
            throw LoopbackAuthServerError.listenerFailed(reason)
        }

        // Non-blocking: accept/read run on the main queue via DispatchSource,
        // and must never block the UI waiting on the browser.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

        let server = LoopbackAuthServer(socketFD: fd)
        server.acceptConnections(path: path)
        return server
    }

    /// Suspends until: a valid GET on `path` arrives, `timeout` elapses, or
    /// `stop()` is called — whichever comes first.
    func awaitCallback(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resume(throwing: .timedOut)
            }
        }
    }

    /// Safe to call with nothing pending, and safe to call twice — once the
    /// continuation has resumed this is a no-op.
    func stop() {
        resume(throwing: .cancelled)
    }

    private func acceptConnections(path: String) {
        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let client = accept(self.socketFD, nil, nil)
                guard client >= 0 else { return }
                _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL, 0) | O_NONBLOCK)
                self.read(from: client, path: path)
            }
        }
        source.resume()
        acceptSource = source
    }

    /// Reads until the end of the request head. A browser's GET has no body,
    /// but it can still arrive split across reads, so bytes accumulate until
    /// the blank line that terminates the head.
    private func read(from client: Int32, path: String) {
        var buffer = Data()
        let source = DispatchSource.makeReadSource(fileDescriptor: client, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                var chunk = [UInt8](repeating: 0, count: 4096)
                let count = recv(client, &chunk, chunk.count, 0)
                guard count > 0 else {
                    source.cancel()
                    close(client)
                    return
                }
                buffer.append(contentsOf: chunk[0..<count])
                guard
                    buffer.count > 16_384 || buffer.range(of: Data("\r\n\r\n".utf8)) != nil,
                    let request = String(data: buffer, encoding: .utf8)
                else { return }
                source.cancel()
                self.respond(to: request, on: client, path: path)
            }
        }
        source.resume()
        connectionSources.append(source)
    }

    /// Only a matching path resolves the sign-in — anything else (a favicon
    /// probe from the browser, say) gets a 404 and leaves the listener waiting
    /// for the real callback.
    private func respond(to request: String, on client: Int32, path: String) {
        guard
            let requestLine = request.split(separator: "\r\n").first,
            let target = requestLine.split(separator: " ").dropFirst().first,
            let components = URLComponents(string: "http://127.0.0.1\(target)"),
            components.path == path
        else {
            send(status: "404 Not Found", html: "", on: client)
            return
        }

        let items = components.queryItems ?? []
        if let code = items.first(where: { $0.name == "code" })?.value {
            send(status: "200 OK", html: Self.successHTML, on: client)
            resume(returning: code)
        } else {
            let reason = items.first(where: { $0.name == "error_description" })?.value
                ?? items.first(where: { $0.name == "error" })?.value
                ?? "Sign-in was cancelled or denied."
            send(status: "200 OK", html: Self.failureHTML, on: client)
            resume(throwing: .invalidCallback(reason))
        }
    }

    private func send(status: String, html: String, on client: Int32) {
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(head.utf8)
        response.append(body)
        response.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let written = Darwin.send(client, raw.baseAddress!.advanced(by: sent), raw.count - sent, 0)
                // The response is a few hundred bytes into an empty loopback
                // buffer; a partial write is possible but a hard failure just
                // means the tab shows nothing, which must not hang the sign-in.
                guard written > 0 else { break }
                sent += written
            }
        }
        close(client)
    }

    private func resume(returning code: String) {
        guard !didResume else { return }
        didResume = true
        continuation?.resume(returning: code)
        continuation = nil
        shutdownSockets()
    }

    private func resume(throwing error: LoopbackAuthServerError) {
        guard !didResume else { return }
        didResume = true
        continuation?.resume(throwing: error)
        continuation = nil
        shutdownSockets()
    }

    private func shutdownSockets() {
        acceptSource?.cancel()
        acceptSource = nil
        connectionSources.forEach { $0.cancel() }
        connectionSources.removeAll()
        close(socketFD)
    }

    private static func describe(_ code: Int32) -> String {
        String(cString: strerror(code))
    }

    private static let successHTML = """
    <!doctype html><html><head><meta charset="utf-8"><title>Nimbus</title></head>
    <body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 80px;">
    <h2>Signed in to Nimbus</h2><p>You can close this tab.</p></body></html>
    """

    private static let failureHTML = """
    <!doctype html><html><head><meta charset="utf-8"><title>Nimbus</title></head>
    <body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 80px;">
    <h2>Sign-in failed</h2><p>You can close this tab and try again from Nimbus.</p></body></html>
    """
}
