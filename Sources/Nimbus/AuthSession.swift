import AppKit
import Foundation

enum AuthState {
    case restoring
    case signedOut
    case signingIn(SupabaseAuthProvider)
    case signedIn(SupabaseAuthUser)
    case failed(String)
}

@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()
    private init() {}

    @Published private(set) var state: AuthState = .restoring

    private let accessTokenStore = KeychainTokenStore()
    private let refreshTokenStore = KeychainSecretStore(account: NimbusSecretAccount.supabaseRefreshToken)

    private static let signInTimeout: TimeInterval = 300
    private static let restoreTimeout: TimeInterval = 10

    private var loopbackServer: LoopbackAuthServer?

    func signIn(provider: SupabaseAuthProvider) {
        // A previous attempt can still own the loopback port — the user opened
        // the browser, never finished, and clicked a provider again. Starting a
        // second listener on the same port fails with "port already in use", so
        // the old one goes down first. The abandoned `Task` sees `.cancelled`
        // and exits without touching `state`.
        stopLoopbackServer()
        state = .signingIn(provider)
        Task {
            do {
                let verifier = PKCE.makeCodeVerifier()
                let server = try await LoopbackAuthServer.start(
                    port: SupabaseConfiguration.authRedirectPort,
                    path: SupabaseConfiguration.authRedirectPath
                )
                loopbackServer = server

                let url = SupabaseAuthClient.authorizationURL(
                    provider: provider,
                    codeChallenge: PKCE.codeChallenge(for: verifier),
                    redirectTo: SupabaseConfiguration.authRedirectURL
                )
                NSWorkspace.shared.open(url)

                let code = try await server.awaitCallback(timeout: Self.signInTimeout)
                stopLoopbackServer()

                let session = try await SupabaseAuthClient.exchangeCode(code, codeVerifier: verifier)
                try store(session)
                state = .signedIn(session.user)
            } catch LoopbackAuthServerError.cancelled {
                // reset() ja levou pra signedOut — nada a fazer.
            } catch {
                stopLoopbackServer()
                state = .failed((error as? LocalizedError)?.errorDescription ?? "Sign-in failed. Try again.")
            }
        }
    }

    func reset() {
        stopLoopbackServer()
        state = .signedOut
    }

    /// Releases the loopback port. Safe to call with nothing in flight, and
    /// safe to call twice — `LoopbackAuthServer.stop()` is a no-op once its
    /// continuation has been resumed.
    private func stopLoopbackServer() {
        loopbackServer?.stop()
        loopbackServer = nil
    }

    func signOut() {
        try? accessTokenStore.delete()
        try? refreshTokenStore.delete()
        state = .signedOut
    }

    func restoreSessionAtLaunch() {
        startRestoreWatchdog()
        Task {
            guard let accessToken = (try? accessTokenStore.accessToken()) ?? nil else {
                state = .signedOut
                return
            }
            if let user = try? await SupabaseAuthClient.fetchUser(accessToken: accessToken) {
                state = .signedIn(user)
                return
            }
            guard let refreshToken = (try? refreshTokenStore.read()) ?? nil else {
                state = .signedOut
                return
            }
            do {
                let session = try await SupabaseAuthClient.refreshSession(refreshToken: refreshToken)
                try store(session)
                state = .signedIn(session.user)
            } catch {
                state = .signedOut
            }
        }
    }

    /// `.restoring` must not be a dead end. The Keychain read below can block
    /// for as long as the system's authorization prompt stays unanswered —
    /// measured at 4s when accepted, and unbounded when it is left alone, which
    /// happens after any rebuild changes the app's signature. Sign-in is now
    /// required to use Nimbus, so a stuck restore would leave the whole app on
    /// a spinner with no way forward; falling back to the sign-in buttons keeps
    /// a path open. A late answer still resolves to `.signedIn` afterwards.
    private func startRestoreWatchdog() {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.restoreTimeout * 1_000_000_000))
            if case .restoring = state {
                state = .signedOut
            }
        }
    }

    private func store(_ session: SupabaseAuthSession) throws {
        try accessTokenStore.save(accessToken: session.accessToken)
        try refreshTokenStore.write(session.refreshToken)
    }
}