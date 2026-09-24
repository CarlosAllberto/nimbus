import AppKit
import SwiftUI

/// Borderless, nonactivating panel for the Spotlight-style tool search.
/// Mirrors `QuickDropPanel`'s shape exactly — same AppKit pattern, just
/// centered on the screen instead of in the corner — so the keyboard, focus
/// and click-outside behavior all match without re-deriving them.
final class SpotlightPanel: NSPanel {
    /// Escape is also handled by the content's `onExitCommand`, but that only
    /// fires while the view holding it is in the responder chain. Handling
    /// `cancelOperation` at the window level makes Escape work no matter which
    /// result currently has focus.
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Owns the panel's lifecycle so `AppDelegate` doesn't have to. Unlike Quick
/// Drop there is no `QuickDropSession`-style importer counter: Spotlight never
/// presents a sheet, so nothing it shows can resign the panel's key status on
/// its own.
@MainActor
final class SpotlightPanelController {
    private var panel: SpotlightPanel?
    private var resignKeyObserver: NSObjectProtocol?
    private let onToolSelected: (String) -> Void

    var isVisible: Bool { panel != nil }

    init(onToolSelected: @escaping (String) -> Void) {
        self.onToolSelected = onToolSelected
    }

    /// Both the hotkey and the status-item menu item call this: open if
    /// closed, or dismiss without picking anything if already open.
    func toggle() {
        if panel != nil {
            close()
        } else {
            open()
        }
    }

    private func open() {
        let panel = makePanel()
        self.panel = panel
        position(panel)
        observeResignKey(for: panel)

        panel.makeKeyAndOrderFront(nil)
        // The window shadow is cached from the alpha at first display; the card
        // fades and scales in, so recompute it once the content is on screen.
        panel.invalidateShadow()
    }

    /// `orderOut`, never `close()`: `close()` posts
    /// `NSWindow.willCloseNotification`, and skipping it sidesteps that whole
    /// class of problem rather than leaning solely on the `object:` filter
    /// already in place on `AppDelegate`'s own observer.
    ///
    /// No restore-previous-app here: Spotlight's whole job is to bring Nimbus
    /// to the front on selection (`showMainWindow`), and Esc/click-outside
    /// have no user-visible "go back to what I was doing" — Quick Drop had
    /// that affordance because dropping a file is a "passing" interaction.
    private func close() {
        guard let panel else { return }
        self.panel = nil
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
        panel.orderOut(nil)
    }

    private func makePanel() -> SpotlightPanel {
        // Borderless, not `.titled`: a titled window reserves a titlebar above
        // the content, so the frame was taller than the card and the card sat
        // that much lower than the requested margin. `canBecomeKey` is
        // overridden, which is what a borderless window needs to take focus.
        // `.nonactivatingPanel` so opening Spotlight does not activate Nimbus:
        // activating raises *every* window the app owns, so the main window
        // would jump in front of whatever the user was working in. Such a panel
        // still becomes key and receives Escape and typing while the app is in
        // the background.
        let panel = SpotlightPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // `.prominent` (see `GlassBackground`) is a deliberately dark pane in
        // both light and dark system appearance. Forcing the *panel's* own
        // appearance — not just a SwiftUI `colorScheme` override — keeps the
        // glass material and its text dark together: a `colorScheme` override
        // alone only recolors the SwiftUI content, while `NSVisualEffectView`/
        // `glassEffect` still read the real system appearance underneath it,
        // so a light system appearance produced light-on-light text.
        panel.appearance = NSAppearance(named: .darkAqua)
        // AppKit computes this from the alpha the window actually renders, so
        // it traces the rounded card. SwiftUI's `.shadow` cannot: the glass
        // backdrop is not a shape it can sample, so it shadows the bounding
        // box and paints a square halo instead.
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        // Never drawn — there is no titlebar — but VoiceOver announces it, and
        // the panel has no visible heading of its own.
        panel.title = "Search Tools"

        panel.onCancel = { [weak self] in
            self?.close()
        }

        let hosting = NSHostingView(
            rootView: SpotlightView(
                onSelect: { [weak self] toolID in
                    self?.close()
                    self?.onToolSelected(toolID)
                },
                onCancel: { [weak self] in
                    self?.close()
                }
            )
        )
        // `NSHostingView` backs itself with an opaque layer, which paints the
        // whole window rect — reading as a dark square behind the rounded card,
        // no matter how the SwiftUI side is clipped.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false

        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        return panel
    }

    /// Centered on the screen under the cursor (fallback `.main`). `visibleFrame`
    /// (not `frame`) is what makes the panel respect the menu bar and notch.
    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    /// Clicking another app resigns key; that is not an intentional
    /// dismissal, so the panel just goes away — nothing to restore.
    private func observeResignKey(for panel: NSPanel) {
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close()
            }
        }
    }
}