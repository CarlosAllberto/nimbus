import Foundation
import CryptoKit

enum SupabaseAuthError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Supabase returned an invalid response."
        case let .httpStatus(status, message): return "Supabase auth failed (\(status)): \(message)"
        }
    }
}

enum SupabaseAuthProvider: String, CaseIterable, Identifiable {
    case google, facebook, github

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .google: "Google"
        case .facebook: "Facebook"
        case .github: "GitHub"
        }
    }
    // Sem pipeline de asset/logo de marca no repo hoje (ToolCatalog inteiro
    // e SF Symbols) — mantem a mesma convencao em vez de introduzir uma
    // nova so pra 3 botoes.
    var icon: String {
        switch self {
        case .google: "globe"
        case .facebook: "person.2.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct SupabaseAuthUser: Sendable {
    let id: String
    let email: String?
    let displayName: String?
}

struct SupabaseAuthSession: Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: SupabaseAuthUser
}

/// PKCE (RFC 7636): `code_verifier` e uma string aleatoria que nunca sai da
/// memoria do processo (nunca vai pro Keychain nem pra disco — so serve pra
/// provar, na troca do `code`, que quem esta trocando e quem abriu o
/// `/authorize`; depois de usado, e descartavel). `code_challenge` e o SHA-256
/// dele, mandado no `/authorize` (o servidor guarda o challenge; na troca,
/// valida contra o verifier).
enum PKCE {
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum SupabaseAuthClient {
    /// So e aberta no browser do sistema (NSWorkspace) — nunca chamada
    /// diretamente pelo app. O login do provider tem que rodar num browser
    /// de verdade, e essa e a razao inteira da feature nao usar
    /// ASWebAuthenticationSession.
    static func authorizationURL(provider: SupabaseAuthProvider, codeChallenge: String, redirectTo: URL) -> URL {
        var components = URLComponents(
            url: SupabaseConfiguration.url.appending(path: "/auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider.rawValue),
            URLQueryItem(name: "redirect_to", value: redirectTo.absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components.url!
    }

    static func exchangeCode(_ code: String, codeVerifier: String) async throws -> SupabaseAuthSession {
        try await tokenRequest(grantType: "pkce", body: ["auth_code": code, "code_verifier": codeVerifier])
    }

    static func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession {
        try await tokenRequest(grantType: "refresh_token", body: ["refresh_token": refreshToken])
    }

    static func fetchUser(accessToken: String) async throws -> SupabaseAuthUser {
        var request = URLRequest(url: SupabaseConfiguration.url.appending(path: "/auth/v1/user"))
        request.setValue(SupabaseConfiguration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try decodeUser(from: data)
    }

    private static func tokenRequest(grantType: String, body: [String: String]) async throws -> SupabaseAuthSession {
        var components = URLComponents(
            url: SupabaseConfiguration.url.appending(path: "/auth/v1/token"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try decodeSession(from: data)
    }

    private static func checkStatus(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseAuthError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
        }
    }

    /// `user_metadata` varia por provider (chaves diferentes pra
    /// nome/avatar) — decodificado via `JSONSerialization` em vez de um
    /// `Decodable` estrito, mesma razao pratica que ja levou
    /// `RawJSONFallbackView` (FormResultView, feature anterior) a existir
    /// pra shapes imprevisiveis.
    private static func decodeSession(from data: Data) throws -> SupabaseAuthSession {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = object["access_token"] as? String,
            let refreshToken = object["refresh_token"] as? String,
            let expiresIn = object["expires_in"] as? Int,
            let userObject = object["user"] as? [String: Any]
        else { throw SupabaseAuthError.invalidResponse }
        return SupabaseAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            user: try decodeUser(fromObject: userObject)
        )
    }

    private static func decodeUser(from data: Data) throws -> SupabaseAuthUser {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseAuthError.invalidResponse
        }
        return try decodeUser(fromObject: object)
    }

    private static func decodeUser(fromObject object: [String: Any]) throws -> SupabaseAuthUser {
        guard let id = object["id"] as? String else { throw SupabaseAuthError.invalidResponse }
        let metadata = object["user_metadata"] as? [String: Any]
        return SupabaseAuthUser(
            id: id,
            email: object["email"] as? String,
            displayName: (metadata?["full_name"] as? String) ?? (metadata?["name"] as? String)
        )
    }
}