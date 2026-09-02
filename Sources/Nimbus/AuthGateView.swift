import SwiftUI

/// Full-window sign-in gate. Nimbus requires an account, so `MainWindowView`
/// shows this instead of the tool catalog whenever there is no live session.
/// It is the only place the provider buttons live — the Account tab in
/// Preferences is read-only, so there is one sign-in surface, not two.
struct AuthGateView: View {
    @ObservedObject private var session = AuthSession.shared

    var body: some View {
        VStack(spacing: 24) {
            header

            switch session.state {
            case .restoring:
                // Never the provider buttons on launch: the saved session is
                // still being validated, and flashing sign-in at someone who
                // is already signed in reads as being logged out.
                progress("Loading your account…")
            case let .signingIn(provider):
                signingIn(provider)
            case .signedOut:
                providerButtons
            case let .failed(message):
                failed(message)
            case .signedIn:
                // MainWindowView switches away from the gate in this state;
                // the branch exists only to keep the switch exhaustive.
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Welcome to Nimbus")
                .font(.title2.bold())
            Text("Sign in to use your tools.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var providerButtons: some View {
        VStack(spacing: 10) {
            ForEach(SupabaseAuthProvider.allCases) { provider in
                Button {
                    session.signIn(provider: provider)
                } label: {
                    HStack(spacing: 10) {
                        ProviderBrandMark(provider: provider)
                        Text("Continue with \(provider.displayName)")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(width: 280)
    }

    private func signingIn(_ provider: SupabaseAuthProvider) -> some View {
        VStack(spacing: 14) {
            progress("Waiting for \(provider.displayName) sign-in in your browser…")
            Button("Cancel") { session.reset() }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 14) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            // Back to the provider list rather than a bare "Dismiss": being
            // sent to an empty window with no way forward is the one thing
            // this screen must never do.
            Button("Try Again") { session.reset() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AuthGateView()
        .frame(width: 640, height: 504)
}
