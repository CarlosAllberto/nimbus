import AppKit
import Combine
import SwiftUI

/// No SwiftUI `App`: its only scene would be `Settings`, and SwiftUI opened
/// that window on every launch. The delegate owns the whole UI instead.
@main
enum NimbusMain {
    @MainActor private static let delegate = AppDelegate()

    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.delegate = delegate
            app.run()
        }
    }
}

/// Nimbus lives only in the menu bar: no Dock icon, no main window. Quick
/// Drop is the whole UI, and Preferences is the one window besides it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?
    private let quickDropController = QuickDropPanelController()
    private var quickDropHotKey: GlobalHotKey?
    private var updateObserver: AnyCancellable?
    private var updateMenuItem: NSMenuItem?
    private var updateSeparatorItem: NSMenuItem?

    /// The real Nimbus mark, shared with the web app's own tray asset, marked
    /// as a template so macOS tints it for a light or dark menu bar instead of
    /// drawing the artwork's own near-white. Falls back to the SF Symbol when
    /// the resource isn't there — a missing icon must not cost the app its
    /// only way in and out of the menu bar.
    private static func statusItemImage() -> NSImage? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard
            let url = bundle.url(forResource: "TrayIcon", withExtension: "png")
                ?? bundle.url(forResource: "TrayIcon", withExtension: "png", subdirectory: "Resources"),
            let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "Nimbus")
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = "Nimbus"
        return image
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.statusItemImage()
        statusItem.button?.toolTip = "Nimbus"
        quickDropController.startWatchingDrags()
        let menu = NSMenu()
        menu.delegate = self

        // Above Quick Drop on purpose: when present, it's the most
        // time-sensitive, actionable item in the menu.
        let updateItem = NSMenuItem(title: "", action: #selector(checkForAppUpdates), keyEquivalent: "")
        updateItem.isHidden = true
        menu.addItem(updateItem)
        let updateSeparator = NSMenuItem.separator()
        updateSeparator.isHidden = true
        menu.addItem(updateSeparator)
        updateMenuItem = updateItem
        updateSeparatorItem = updateSeparator

        // Shows the global shortcut in the menu, which is the only place it is
        // discoverable.
        let quickDropItem = menu.addItem(
            withTitle: String(localized: "Quick Drop", bundle: .l10n),
            action: #selector(toggleQuickDrop),
            keyEquivalent: QuickDropShortcut.menuKeyEquivalent
        )
        quickDropItem.keyEquivalentModifierMask = QuickDropShortcut.menuModifiers
        menu.addItem(.separator())
        // Always visible, unlike `updateItem` above (which only shows once
        // Sparkle's own background schedule has already found something on
        // its own): this is the manual "check right now" path, showing
        // Sparkle's usual dialog either way — a found update, or "you're up
        // to date."
        menu.addItem(withTitle: String(localized: "Check for Updates…", bundle: .l10n), action: #selector(checkForAppUpdates), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Preferences…", bundle: .l10n), action: #selector(showPreferences), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Nimbus", bundle: .l10n), action: #selector(quit), keyEquivalent: "")
        statusItem.menu = menu

        // RegisterEventHotKey fails silently if the combination is already
        // owned by another process; the Quick Drop menu item above stays the
        // reachable path to the feature either way.
        quickDropHotKey = GlobalHotKey(
            keyCode: QuickDropShortcut.keyCode,
            modifiers: QuickDropShortcut.modifiers
        ) { [weak self] in
            self?.quickDropController.toggle()
        }

        observeUpdateChanges()
        // Starts Sparkle's updater and its own background check schedule
        // (SUEnableAutomaticChecks/SUScheduledCheckInterval in Info.plist).
        // `UpdateIndicator` only ever changes in response to its delegate
        // callbacks now — nothing here polls anything itself.
        _ = AppUpdater.shared
    }

    /// Keeps the status-bar update line in step with the checker.
    private func observeUpdateChanges() {
        updateObserver = UpdateIndicator.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.refreshUpdateMenuItem() }
            }
        }
        refreshUpdateMenuItem()
    }

    private func refreshUpdateMenuItem() {
        guard let updateMenuItem else { return }
        guard let info = UpdateIndicator.shared.available else {
            updateMenuItem.isHidden = true
            updateSeparatorItem?.isHidden = true
            return
        }
        updateMenuItem.title = String(localized: "Update Available (\(info.versionString))", bundle: .l10n)
        updateMenuItem.isHidden = false
        updateSeparatorItem?.isHidden = false
    }

    @objc private func checkForAppUpdates() {
        AppUpdater.shared.checkForUpdates()
    }

    @objc private func toggleQuickDrop() {
        quickDropController.toggle()
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
            window.title = String(localized: "Nimbus Preferences", bundle: .l10n)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    /// Menu-bar-resident: closing Preferences must not end the app. The user
    /// leaves through Quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        // `GlobalHotKey` can't rely on `deinit` for this — see its doc
        // comment on `unregister()`.
        quickDropHotKey?.unregister()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Background, not `checkForUpdates()`: a menu open must never pop
        // Sparkle's own alert on its own — it only refreshes what
        // `UpdateIndicator` shows, silently.
        AppUpdater.shared.checkForUpdatesInBackground()
    }
}
