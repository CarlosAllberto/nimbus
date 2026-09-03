import Foundation

/// Mirrors `version.json`, published by CI's `publish-build` job
/// (`.github/workflows/ci.yml`) alongside `Nimbus.zip` in the "latest"
/// release on `nimbus-desktop-releases` — `build` is `github.run_number`,
/// monotonically increasing per workflow run regardless of which commit
/// triggered it.
struct UpdateInfo: Decodable, Equatable {
    let build: Int
    let sha: String
    let builtAt: String
}

enum UpdateChecker {
    static let versionURL = URL(string: "https://github.com/CarlosAllberto/nimbus-desktop-releases/releases/download/latest/version.json")!
    static let releasePageURL = URL(string: "https://github.com/CarlosAllberto/nimbus-desktop-releases/releases/latest")!

    /// CI stamps the real build number into Info.plist before packaging (see
    /// ci.yml). A local `swift build`/Xcode debug run never goes through
    /// that step, so it stays at the checked-in placeholder — always older
    /// than any published build, which is the right default: there is
    /// nothing to usefully "update" a local build to.
    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// Fails closed on purpose (returns nil on any error): a check that
    /// can't complete must never crash or block startup, and nil just means
    /// "nothing to report this time" — the next check (menu open, or the
    /// next launch) tries again.
    static func checkForUpdate() async -> UpdateInfo? {
        guard
            let (data, response) = try? await URLSession.shared.data(from: versionURL),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let info = try? JSONDecoder().decode(UpdateInfo.self, from: data),
            info.build > currentBuild
        else { return nil }
        return info
    }
}

/// Ponte AppKit/qualquer-view -> Preferences, mesmo padrao
/// `@MainActor ObservableObject` singleton que `UsageIndicator` ja usa.
@MainActor
final class UpdateIndicator: ObservableObject {
    static let shared = UpdateIndicator()
    private init() {}

    @Published private(set) var available: UpdateInfo?

    func update(_ info: UpdateInfo?) {
        available = info
    }
}
