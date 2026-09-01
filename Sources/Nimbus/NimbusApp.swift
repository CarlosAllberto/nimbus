import AppKit
import SwiftUI

@main
struct NimbusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("nimbusTheme") private var theme: NimbusTheme = .system

    var body: some Scene {
        WindowGroup("") {
            MainWindowView()
                .preferredColorScheme(theme.colorScheme)
        }
        .defaultSize(width: 640, height: 504)
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

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
    }

    @objc private func toggleQuickDrop() {
        quickDropController.toggle()
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
        // the user just asked to see.
        guard quickDropController.isVisible == false else { return }
        guard let mainWindow, mainWindow.isVisible else { return }
        mainWindow.orderFrontRegardless()
        mainWindow.makeKey()
    }

    /// Clicking the Dock tile on an app with no open window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showMainWindow() }
        return true
    }

    @objc private func showMainWindow() {
        guard let window = mainWindow ?? NSApp.windows.first(where: { $0.contentViewController != nil }) else {
            DispatchQueue.main.async { [weak self] in
                self?.showMainWindow()
            }
            return
        }
        mainWindow = window
        window.isReleasedWhenClosed = false
        observeClose(of: window)

        // The app lives in the menu bar, but while its window is up it behaves like
        // a normal app: Dock tile, ⌘Tab entry, recents. `windowWillClose` puts it
        // back to accessory so an idle Nimbus stays out of the way.
        NSApp.setActivationPolicy(.regular)
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
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)

        if NSApp.isActive {
            window.makeKey()
        }
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
        SidecarProcess.shared.shutdown()
    }
}
