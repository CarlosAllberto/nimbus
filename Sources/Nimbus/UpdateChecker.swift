import Foundation
import Sparkle

/// What the 2 passive UI surfaces (status-bar menu item, Preferences line)
/// show once Sparkle's own background check finds something
/// newer than what's running.
struct UpdateInfo: Equatable {
    let versionString: String
}

/// Bridge from AppKit/any view to UI, a `@MainActor ObservableObject`
/// singleton. Mirrors what `AppUpdater` already
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
        // A bare `swift build` executable has no Info.plist for Sparkle to read
        // (feed URL, signing key), so it would greet every launch with an error
        // alert. Only a real `.app` starts the updater.
        let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        controller = SPUStandardUpdaterController(startingUpdater: isAppBundle, updaterDelegate: self, userDriverDelegate: nil)
    }

    /// What every "Update Available" click (menu item, Preferences button) calls — unlike the silent background check this
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
