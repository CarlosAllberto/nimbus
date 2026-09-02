import Foundation
import Security

enum NimbusAPIError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Nimbus returned an invalid response."
        case let .httpStatus(status, message):
            if let extracted = Self.extractErrorMessage(from: message) {
                return extracted
            }
            return "Nimbus request failed (\(status)): \(message)"
        }
    }

    /// Every sidecar form route answers an error as `{"error": "..."}` — this
    /// pulls just that message out instead of showing the raw JSON body. Not
    /// JSON (some file-tool routes answer plain text) falls through unchanged.
    private static func extractErrorMessage(from body: String) -> String? {
        guard
            let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["error"] as? String
        else { return nil }
        return message
    }
}

enum NimbusEndpoint {
    private static let aliases: [String: String] = [
        "whois-scan": "whois",
        "wa-link": "whatsapp-link",
        "password-generator": "generate-password",
        "html-minify": "minify-unminify",
        "js-minify": "minify-unminify-js"
    ]

    static func path(for tool: NimbusTool) -> String {
        let segment = aliases[tool.id] ?? tool.id
        return "/api/tools/\(tool.group.rawValue)/\(segment)"
    }
}

struct NimbusConfiguration: Sendable {
    var apiBaseURL: URL
    static let production = NimbusConfiguration(apiBaseURL: URL(string: "https://www.nimbushelp.com")!)
}

protocol NimbusTokenProvider: Sendable {
    /// The header this provider wants injected into every request, if any —
    /// name and value together, so different backends (a bearer token today,
    /// the sidecar's shared secret tomorrow) don't each need their own
    /// injection point in `NimbusAPIClient`.
    func authorizationHeader() throws -> (name: String, value: String)?
}

struct EmptyTokenProvider: NimbusTokenProvider {
    func authorizationHeader() throws -> (name: String, value: String)? { nil }
}

/// The sidecar's per-run shared secret, sent as `X-Nimbus-Secret` rather than
/// `Authorization: Bearer` — it authenticates the local process, not a user.
struct SidecarTokenProvider: NimbusTokenProvider {
    let secret: String

    func authorizationHeader() throws -> (name: String, value: String)? {
        ("X-Nimbus-Secret", secret)
    }
}

/// Generic Keychain read/write for a single service, keyed by account.
/// `KeychainTokenStore` (a Supabase access token) and the two API-key stores
/// below (Gemini, PageSpeed) are different accounts under the same service —
/// the actual Keychain calls don't know or care what the secret is.
final class KeychainSecretStore: @unchecked Sendable {
    private let service: String
    private let account: String

    init(service: String = "com.treendz.nimbus", account: String) {
        self.service = service
        self.account = account
    }

    func read() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    /// Clearing a Preferences field should remove the Keychain item, not
    /// leave an empty string behind that would still "count" as present.
    func delete() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

/// Account names for the two API-key secrets. Not an enum of behavior — just
/// named constants so `KeychainSecretStore(account:)` call sites don't repeat
/// string literals that have to match between PreferencesView and SidecarProcess.
enum NimbusSecretAccount {
    static let geminiAPIKey = "gemini-api-key"
    static let pageSpeedAPIKey = "google-pagespeed-api-key"
    static let supabaseRefreshToken = "supabase-refresh-token"
}

final class KeychainTokenStore: NimbusTokenProvider, @unchecked Sendable {
    private let store: KeychainSecretStore

    init(service: String = "com.treendz.nimbus", account: String = "supabase-access-token") {
        self.store = KeychainSecretStore(service: service, account: account)
    }

    func accessToken() throws -> String? { try store.read() }

    func authorizationHeader() throws -> (name: String, value: String)? {
        guard let token = try accessToken() else { return nil }
        return ("Authorization", "Bearer \(token)")
    }

    func save(accessToken: String) throws { try store.write(accessToken) }

    func delete() throws { try store.delete() }
}

/// An extra multipart part beyond the primary `file` — Device Wrapper's
/// optional background image is the first tool that needs one.
struct NimbusExtraFile: Sendable {
    let fieldName: String
    let data: Data
    let filename: String
}

extension URLSession {
    /// A tool run can take minutes, and the sidecar sends nothing at all until
    /// it finishes — so `URLSession.shared`'s 60-second idle timeout would
    /// cancel a long video encode partway through and report it as a network
    /// failure. The work is local; there is no reason to give up early.
    static let nimbusTool: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 3600
        configuration.timeoutIntervalForResource = 3600
        return URLSession(configuration: configuration)
    }()
}

struct NimbusAPIClient: Sendable {
    let configuration: NimbusConfiguration
    let tokenProvider: any NimbusTokenProvider
    private let session: URLSession

    init(configuration: NimbusConfiguration = .production, tokenProvider: any NimbusTokenProvider = EmptyTokenProvider(), session: URLSession = .nimbusTool) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func process(
        tool: NimbusTool,
        file: Data,
        filename: String,
        // Most routes call the main part `file`, but the video ones call it
        // `video` — the web app's own naming, kept so the routes stay
        // comparable to theirs.
        fileFieldName: String = "file",
        fields: [String: String] = [:],
        extraFiles: [NimbusExtraFile] = []
    ) async throws -> (Data, URLResponse) {
        let endpoint = configuration.apiBaseURL.appending(path: NimbusEndpoint.path(for: tool))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let boundary = "NimbusBoundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let header = try tokenProvider.authorizationHeader() {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        request.httpBody = multipartBody(
            boundary: boundary,
            file: file,
            filename: filename,
            fileFieldName: fileFieldName,
            fields: fields,
            extraFiles: extraFiles
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NimbusAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NimbusAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return (data, response)
    }

    /// Like `process(...)` but for form tools: field values (and, only for
    /// QR Code, an optional icon file) instead of a dropped primary file.
    /// Every sidecar form route reads `request.formData()` the same way the
    /// file routes already do, so there is one wire protocol, not two.
    func processForm(
        tool: NimbusTool,
        fields: [String: String] = [:],
        files: [NimbusExtraFile] = []
    ) async throws -> (Data, URLResponse) {
        let endpoint = configuration.apiBaseURL.appending(path: NimbusEndpoint.path(for: tool))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let boundary = "NimbusBoundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let header = try tokenProvider.authorizationHeader() {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        request.httpBody = formOnlyMultipartBody(boundary: boundary, fields: fields, files: files)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NimbusAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NimbusAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return (data, response)
    }

    private func formOnlyMultipartBody(boundary: String, fields: [String: String], files: [NimbusExtraFile]) -> Data {
        var body = Data()
        let line = "\r\n"
        for (key, value) in fields {
            body.append(Data("--\(boundary)\(line)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\(line)\(line)\(value)\(line)".utf8))
        }
        for file in files {
            body.append(Data("--\(boundary)\(line)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(file.data)
            body.append(Data(line.utf8))
        }
        body.append(Data("--\(boundary)--\(line)".utf8))
        return body
    }

    private func multipartBody(
        boundary: String,
        file: Data,
        filename: String,
        fileFieldName: String,
        fields: [String: String],
        extraFiles: [NimbusExtraFile]
    ) -> Data {
        var body = Data()
        let line = "\r\n"
        for (key, value) in fields {
            body.append(Data("--\(boundary)\(line)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(key)\"\(line)\(line)\(value)\(line)".utf8))
        }
        body.append(Data("--\(boundary)\(line)".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(file)
        body.append(Data(line.utf8))
        for extra in extraFiles {
            body.append(Data("--\(boundary)\(line)".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(extra.fieldName)\"; filename=\"\(extra.filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(extra.data)
            body.append(Data(line.utf8))
        }
        body.append(Data("--\(boundary)--\(line)".utf8))
        return body
    }
}
