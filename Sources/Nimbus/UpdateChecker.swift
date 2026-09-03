import Foundation
import Sparkle

/// What the 3 passive UI surfaces (status-bar menu item, Preferences line,
/// sidebar badge) show once Sparkle's own background check finds something
/// newer than what's running.
struct UpdateInfo: Equatable {
    let versionString: String
}

/// Ponte AppKit/qualquer-view -> UI, mesmo padrao `@MainActor ObservableObject`
/// singleton que `UsageIndicator` ja usa. Mirrors what `AppUpdater` already
/// knows — there is no separate polling here; `AppUpdater`'s delegate
/// callbacks are the only thing that writes to this.
@MainActor
final class UpdateIndicator: ObservableObject {
    static let shared = UpdateIndicator()
    private init() {}

    @Published private(set) var available: UpdateInfo?

    func update(_ info: UpdateInfo?) {
        available = info
    }
}

/// Owns Sparkle's updater for the app's lifetime. `SPUStandardUpdaterController`
/// runs its own background schedule (`SUEnableAutomaticChecks` +
/// `SUScheduledCheckInterval` in Info.plist) against `SUFeedURL`
/// (nimbus-desktop-releases' "latest" release, `appcast.xml`, published and
/// EdDSA-signed by CI's publish-build job) and, through the default
/// `SPUStandardUserDriver`, pops Sparkle's own native "Update Available"
/// alert — release notes, Install & Relaunch — with no custom UI code needed
/// here at all.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    // Implicitly-unwrapped: `SPUUpdater.delegate` isn't settable after
    // construction, so `self` has to be handed to the controller's own
    // initializer as `updaterDelegate` — which needs `super.init()` to have
    // already run. Set exactly once, immediately after, and never nil again.
    private(set) var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    /// What every "Update Available" click (menu item, Preferences button,
    /// sidebar badge) calls — unlike the silent background check this
    /// controller already runs on its own schedule, this always shows
    /// Sparkle's UI, including a "you're up to date" alert if nothing new
    /// has landed since the last background check.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// What `menuWillOpen` calls: refreshes `UpdateIndicator` (via the same
    /// delegate callbacks below) without ever popping Sparkle's alert on its
    /// own, unlike `checkForUpdates()`.
    func checkForUpdatesInBackground() {
        controller.updater.checkForUpdatesInBackground()
    }

    /// Sparkle's delegate callbacks aren't documented as arriving on any
    /// particular queue, so these stay `nonisolated` and hop to the main
    /// actor themselves rather than assuming the call already landed there.
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            UpdateIndicator.shared.update(UpdateInfo(versionString: item.displayVersionString))
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            UpdateIndicator.shared.update(nil)
        }
    }
}
