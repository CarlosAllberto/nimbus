import AppKit
import Combine
import SwiftUI

@main
struct NimbusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("nimbusTheme") private var theme: NimbusTheme = .system

    var body: some Scene {
        Window("", id: "main") {
            MainWindowView()
                .preferredColorScheme(theme.colorScheme)
        }
        .defaultSize(width: 640, height: 504)
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        // DEFENSIVE: Nimbus no longer registers any URL scheme or accepts
        // external open events (the auth callback switched to loopback HTTP
        // in `LoopbackAuthServer.swift`), so today there is no event that
        // would reach here. Measured: without this empty matcher, when an
        // external event *did* exist (the old `nimbus://` callback) SwiftUI
        // built a second instance of this scene — `MainWindowView` appeared
        // twice and a third `NSWindow` was added on top of the existing one,
        // all before the AppDelegate saw the URL. The empty matcher tells
        // SwiftUI this scene wants no external events at all, so even if a
        // scheme/user-activity/Handoff is ever wired up in the future, the
        // Scene refuses to spawn a duplicate. Costs zero today.
        .handlesExternalEvents(matching: [])

        Settings {
            PreferencesView(theme: $theme)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private let quickDropController = QuickDropPanelController()
    private var quickDropHotKey: GlobalHotKey?
    private var spotlightController: SpotlightPanelController?
    private var spotlightHotKey: GlobalHotKey?
    /// Tracks whether the *last* window of Nimbus to take key focus was
    /// `mainWindow`. Updated in real time via `NSWindow.didBecomeKeyNotification`
    /// so the value reflects what was true right before focus left the app
    /// — `NSApp.keyWindow` is unreliable during `applicationDidBecomeActive`
    /// (it can be nil while the app is still in the middle of reactivating,
    /// so a guard based on it can't tell whether Preferences was the window
    /// the user was last looking at when the app last regained focus for any
    /// reason).
    ///
    /// `true` means the main window was last in focus (or no other window has
    /// taken focus yet), so `applicationDidBecomeActive` is allowed to raise
    /// it. `false` means another Nimbus-owned window (today just Preferences,
    /// but the check is structural) was the last one in focus, so
    /// `applicationDidBecomeActive` leaves it alone — that window updates
    /// itself from `AuthSession.shared` in its own time.
    private var lastKeyWindowWasMain = true
    private var keyWindowObserver: NSObjectProtocol?
    private var authObserver: AnyCancellable?
    private var titlebarObserver: NSKeyValueObservation?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "Nimbus")
        statusItem.button?.toolTip = "Nimbus"
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Nimbus", action: #selector(showMainWindow), keyEquivalent: "")

        // Shows the global shortcut in the menu, which is the only place it is
        // discoverable.
        let spotlightItem = menu.addItem(
            withTitle: "Search Tools",
            action: #selector(toggleSpotlight),
            keyEquivalent: SpotlightShortcut.menuKeyEquivalent
        )
        spotlightItem.keyEquivalentModifierMask = SpotlightShortcut.menuModifiers
        let quickDropItem = menu.addItem(
            withTitle: "Quick Drop",
            action: #selector(toggleQuickDrop),
            keyEquivalent: QuickDropShortcut.menuKeyEquivalent
        )
        quickDropItem.keyEquivalentModifierMask = QuickDropShortcut.menuModifiers
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nimbus", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
        DispatchQueue.main.async { [weak self] in
            self?.showMainWindow()
        }

        // RegisterEventHotKey fails silently if the combination is already
        // owned by another process; the Quick Drop menu item above stays the
        // reachable path to the feature either way.
        quickDropHotKey = GlobalHotKey(
            keyCode: QuickDropShortcut.keyCode,
            modifiers: QuickDropShortcut.modifiers
        ) { [weak self] in
            self?.quickDropController.toggle()
        }

        // Same silent-failure story as Quick Drop: the Search Tools menu item
        // above is the alternate path if ⌘⇧Space is owned elsewhere.
        let spotlightController = SpotlightPanelController(onToolSelected: { [weak self] toolID in
            SpotlightNavigator.shared.select(toolID)
            self?.showMainWindow()
        })
        self.spotlightController = spotlightController

        spotlightHotKey = GlobalHotKey(
            keyCode: SpotlightShortcut.keyCode,
            modifiers: SpotlightShortcut.modifiers
        ) { [weak self] in
            self?.spotlightController?.toggle()
        }

        AuthSession.shared.restoreSessionAtLaunch()

        observeKeyWindowChanges()
        observeAuthChanges()
    }

    /// Signing in swaps the window's root content (the sign-in gate gives way
    /// to the tool catalog), and SwiftUI re-applies its own `.windowStyle` when
    /// that happens — which resets `titlebarAppearsTransparent` and leaves the
    /// titlebar material drawing over the tool title, blurring it. Re-applying
    /// the chrome after the swap keeps the window looking the same on both
    /// sides of sign-in. (Same root cause as the reopen path in `adopt`.)
    private func observeAuthChanges() {
        authObserver = AuthSession.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let window = self.mainWindow else { return }
                    self.applyChrome(to: window)
                }
            }
        }
    }

    /// SwiftUI re-applies its own `.windowStyle` whenever it rebuilds the
    /// window's root content — signing in, most visibly — and that sets
    /// `titlebarAppearsTransparent` back to false, leaving the titlebar
    /// material blurring the tool title underneath. Re-applying the chrome one
    /// run-loop tick later fixed the common case but is a race: measured at
    /// launch, the reset lands at ~0.2s and the correction at ~0.5s, and
    /// anything that reorders those (a debugger attached, a slower machine)
    /// brings the blur back. Watching the property instead is order-independent
    /// — whoever sets it false, it goes straight back.
    private func observeTitlebarStyle(of window: NSWindow) {
        titlebarObserver = window.observe(\.titlebarAppearsTransparent, options: [.new]) { observed, change in
            guard change.newValue == false else { return }
            MainActor.assumeIsolated {
                observed.titlebarAppearsTransparent = true
            }
        }
    }

    /// Subscribes to every window in the app becoming key, no `object:`
    /// filter — we need to react to *any* Nimbus window (Preferences is the
    /// only other one today, but the comparison is structural). `mainWindow`
    /// can still be nil when this fires (the first window to become key
    /// might be Preferences if the user opened Preferences very early), so
    /// the comparison has to tolerate that.
    private func observeKeyWindowChanges() {
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastKeyWindowWasMain = (window === self.mainWindow)
            }
        }
    }

    /// Quick Drop and Spotlight reach the tools without the main window, so
    /// they have to respect the sign-in gate too — otherwise the shortcuts are
    /// a way around it. Signed out, they raise the window (which is showing
    /// `AuthGateView`) instead of opening their panel, so the user lands on the
    /// one sign-in surface rather than a third copy of it.
    private var isSignedIn: Bool {
        if case .signedIn = AuthSession.shared.state { return true }
        return false
    }

    @objc private func toggleQuickDrop() {
        guard isSignedIn else { showMainWindow(); return }
        quickDropController.toggle()
    }

    @objc private func toggleSpotlight() {
        guard isSignedIn else { showMainWindow(); return }
        spotlightController?.toggle()
    }

    /// `showSettingsWindow:` is the selector SwiftUI's `Settings` scene
    /// registers on the app; there is no typed API to trigger it from AppKit.
    @objc private func showPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Quick Drop activates the app to get a real key window (see
        // QuickDropPanel.swift). Without this guard, that activation would
        // raise the main window right on top of — or instead of — the panel
        // the user just asked to see. Same story for Spotlight: opening it
        // alone must not yank the main window up in front of the panel.
        guard quickDropController.isVisible == false, spotlightController?.isVisible != true else { return }
        // Preferences and the main window both belong to Nimbus; if
        // Preferences was the last window the user had focus on, becoming
        // active again (for any reason) should not yank the main window in
        // front of it. `lastKeyWindowWasMain`, tracked live by
        // `observeKeyWindowChanges()`, is what lets this tell the two apart
        // — `NSApp.keyWindow` is unreliable mid-reactivation.
        guard lastKeyWindowWasMain else { return }
        guard let mainWindow, mainWindow.isVisible else { return }
        mainWindow.orderFrontRegardless()
        mainWindow.makeKey()
    }

    /// Clicking the Dock tile on an app with no open window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showMainWindow() }
        return true
    }

    /// Blindagem: garante que fechar a mainWindow nao termina o app. O
    /// contrato do Nimbus e menu-bar-resident; o usuario sai via Quit ou
    /// pela action da status bar. `Window(id:)` documentadamente nao muda
    /// esse comportamento (o default de NSApplication e false pra apps
    /// sem nenhuma window), mas explicitar e zero custo.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func showMainWindow() {
        // Fast path: cached main window is already up. This is the common
        // case (menu click while window is visible, Spotlight selecting a
        // tool, etc.) -- raise it and return.
        if let mainWindow, mainWindow.isVisible {
            mainWindow.makeKeyAndOrderFront(nil)
            mainWindow.orderFrontRegardless()
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            if NSApp.isActive {
                mainWindow.makeKey()
            }
            return
        }

        // Window is missing/closed. With `Window(id: "main")` (not
        // `WindowGroup`), the only documented way to bring it back is
        // SwiftUI's `openWindow(id:)` -- `MainWindowView` captured that
        // action into `MainWindowOpener` at appear. We still fall back to
        // the `NSApp.windows` lookup first because that path handles the
        // race where the View hasn't been built yet but the NSWindow
        // already exists (cold launch, first time the menu is invoked
        // before SwiftUI has rendered the View).
        if let window = NSApp.windows.first(where: { $0.contentViewController != nil }) {
            adopt(window: window)
            return
        }

        MainWindowOpener.shared.openMain()

        // `openMain()` dispatches `openWindow(id:)`, which makes SwiftUI
        // build a new NSWindow -- but the window isn't necessarily there
        // on this same run-loop tick (the SwiftUI render pass that creates
        // the NSWindow is queued). Adopt it on the next main-queue tick,
        // same pattern the original `showMainWindow` used before the
        // openWindow bridge existed. Without this follow-up, the freshly
        // created window would never get its chrome configured, no
        // `windowWillClose` observer, and `mainWindow` would stay nil --
        // which would in turn break the OAuth `applicationDidBecomeActive`
        // guard that needs `lastKeyWindowWasMain` to track when this window
        // becomes key.
        DispatchQueue.main.async { [weak self] in
            self?.adoptMainWindowIfPresent()
        }
    }

    /// Try once to find and adopt the main window -- used after
    /// `MainWindowOpener.openMain()` to pick up the window SwiftUI will
    /// create in response. Self-terminating: succeeds via `adopt` (which
    /// returns) or finds nothing (returns). No retry loop, matching the
    /// single-retry shape of the pre-`Window(id:)` version.
    ///
    /// Important: the cached `mainWindow` may still be the *old* NSWindow
    /// (we set `isReleasedWhenClosed = false`, so AppKit keeps the object
    /// around after the user closes it -- but that object is no longer the
    /// live scene's NSWindow). So the condition for "we need to adopt" is
    /// "cached window is nil OR not visible AND a different window has a
    /// content view controller" -- the latter covers the case where a new
    /// `Window(id:)` instance has appeared since the cache was populated.
    private func adoptMainWindowIfPresent() {
        if let mainWindow, mainWindow.isVisible {
            return
        }
        if let window = NSApp.windows.first(where: { $0.contentViewController != nil && $0 !== mainWindow }) {
            adopt(window: window)
        }
    }

    /// Configures the `NSWindow` that backs the main `Window(id:)` Scene
    /// the first time we see it: caches it, sets up the chrome SwiftUI
    /// doesn't (no titlebar text, transparent titlebar, fixed size), and
    /// observes its `willClose` so we can return to accessory activation
    /// policy once it's gone.
    private func adopt(window: NSWindow) {
        mainWindow = window
        window.isReleasedWhenClosed = false
        observeClose(of: window)
        observeTitlebarStyle(of: window)

        // The app lives in the menu bar, but while its window is up it behaves like
        // a normal app: Dock tile, ⌘Tab entry, recents. `windowWillClose` puts it
        // back to accessory so an idle Nimbus stays out of the way.
        NSApp.setActivationPolicy(.regular)
        applyChrome(to: window)
        // On the reopen path (`openWindow(id:)` after the user closed the
        // window) SwiftUI applies its own `.windowStyle` *after* this call and
        // resets `titlebarAppearsTransparent` to false — measured: transparent
        // on a cold launch, opaque after close+reopen. A second pass on the
        // next tick makes a reopened window match a freshly launched one.
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            self.applyChrome(to: window)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)

        if NSApp.isActive {
            window.makeKey()
        }
    }

    /// The window chrome SwiftUI doesn't supply: no titlebar text, transparent
    /// titlebar, fixed size, no zoom button. Applied on adoption and once more
    /// on the next run-loop tick — see the call site for why the second pass
    /// is needed on the reopen path.
    private func applyChrome(to window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.formUnion([.titled, .closable, .miniaturizable, .fullSizeContentView])
        // Fixed size: no drag-to-resize handles/cursor, and the zoom button
        // below is hidden rather than just disabled since there is nothing
        // for it to do.
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.closeButton)?.isEnabled = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setContentSize(NSSize(width: 640, height: 504))
    }

    /// Observed through the notification rather than by becoming the window's
    /// delegate, which SwiftUI owns for a `WindowGroup` window.
    private func observeClose(of window: NSWindow) {
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.willCloseNotification, object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        // `GlobalHotKey` can't rely on `deinit` for this — see its doc
        // comment on `unregister()`.
        quickDropHotKey?.unregister()
        spotlightHotKey?.unregister()
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
        SidecarProcess.shared.shutdown()
    }
}
