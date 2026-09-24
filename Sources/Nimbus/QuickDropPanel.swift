import AppKit
import SwiftUI

/// An activating, borderless-looking panel. `.fileImporter` presents
/// `NSOpenPanel` as a sheet, which is unusable if the owning app is not
/// active, and Escape/Tab need a real key window — so, unlike file-drop
/// zones elsewhere in the app, Quick Drop activates Nimbus on open. It still
/// never touches the activation *policy*: an `.accessory` app can activate,
/// take keyboard input, and show an open panel; it just has no Dock icon.
/// Flipping the policy to `.regular` would flash a Dock icon on every
/// invocation — the opposite of the intended feel.
final class QuickDropPanel: NSPanel {
    /// Escape is also handled by the content's `onExitCommand`, but that only
    /// fires while the view holding it is in the responder chain. Handling
    /// `cancelOperation` at the window level makes Escape work no matter which
    /// well currently has focus.
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Tracks how many file importers are currently presented across the four
/// wells. An `Int`, not a `Bool`, so that one well's transition settling
/// can't stomp on another's. `.fileImporter` shows `NSOpenPanel` as a sheet,
/// which resigns the panel's key status; without this guard,
/// `windowDidResignKey` would tear the panel down from underneath the open
/// dialog the moment a well is tapped.
@MainActor
final class QuickDropSession: ObservableObject {
    @Published var importerDepth = 0
}

/// Owns the panel's lifecycle so `AppDelegate` doesn't have to. The panel's
/// content — and its `QuickDropSession` — is rebuilt from scratch on every
/// open, so dropped-then-closed files never survive a close.
@MainActor
final class QuickDropPanelController {
    /// How far the *window* sits from the visible frame. The window is larger
    /// than the card by `shadowMargin` on every side, so it overhangs by the
    /// difference — leaving the card itself `screenInsetTop`/`screenInsetTrailing`
    /// from the respective edge.
    private static let windowMarginTop = QuickDropMetrics.screenInsetTop - QuickDropMetrics.shadowMargin
    private static let windowMarginTrailing = QuickDropMetrics.screenInsetTrailing - QuickDropMetrics.shadowMargin

    private var panel: QuickDropPanel?
    private var resignKeyObserver: NSObjectProtocol?
    private var session: QuickDropSession?
    private var previousFrontmostApp: NSRunningApplication?

    var isVisible: Bool { panel != nil }

    /// Both the hotkey and the status-item menu item call this: open if
    /// closed, or dismiss (intentionally, restoring focus) if already open.
    func toggle() {
        if panel != nil {
            close(restoringPreviousApp: true)
        } else {
            open()
        }
    }

    private func open() {
        previousFrontmostApp = NSWorkspace.shared.frontmostApplication

        let session = QuickDropSession()
        self.session = session

        let panel = makePanel(session: session)
        self.panel = panel
        position(panel)
        observeResignKey(for: panel)

        panel.makeKeyAndOrderFront(nil)
        // The window shadow is cached from the alpha at first display; the card
        // fades and scales in, so recompute it once the content is on screen.
        panel.invalidateShadow()
    }

    /// `orderOut`, never `close()`: `close()` posts
    /// `NSWindow.willCloseNotification`, and skipping it sidesteps that
    /// whole class of problem rather than leaning solely on the `object:`
    /// filter already in place on `AppDelegate`'s own observer.
    ///
    /// Every dismissal path — hotkey/menu toggle, click-outside, Escape —
    /// routes through this one method, and it is the sole place that checks
    /// `importerDepth`. A file-importer sheet in flight must block the panel
    /// from going away out from under it regardless of *why* something is
    /// trying to close it; checking this in only one of the callers (as a
    /// previous version did) left the others free to reintroduce the bug.
    private func close(restoringPreviousApp: Bool) {
        guard let panel else { return }
        guard (session?.importerDepth ?? 0) == 0 else { return }
        self.panel = nil
        session = nil
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
        panel.orderOut(nil)

        if restoringPreviousApp {
            previousFrontmostApp?.activate(options: [])
        }
        previousFrontmostApp = nil
    }

    private func makePanel(session: QuickDropSession) -> QuickDropPanel {
        // Borderless, not `.titled`: a titled window reserves a titlebar above
        // the content, so the frame was taller than the card and the card sat
        // that much lower than the requested margin. `canBecomeKey` is
        // overridden, which is what a borderless window needs to take focus.
        // `.nonactivatingPanel` so opening Quick Drop does not activate Nimbus:
        // activating raises *every* window the app owns, so the main window
        // would jump in front of whatever the user was working in. Such a panel
        // still becomes key and receives Escape and typing while the app is in
        // the background. The app is activated later, only when a well presents
        // its file importer, since `NSOpenPanel` needs an active app.
        let panel = QuickDropPanel(
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
        panel.title = "Quick Drop"

        panel.onCancel = { [weak self] in
            self?.close(restoringPreviousApp: true)
        }

        let hosting = NSHostingView(
            rootView: QuickDropView(session: session, onDismiss: { [weak self] in
                self?.close(restoringPreviousApp: true)
            })
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

    /// The screen under the cursor, falling back to `.main`. `visibleFrame`
    /// (not `frame`) is what makes the panel respect the menu bar and notch.
    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - Self.windowMarginTrailing,
            y: visible.maxY - size.height - Self.windowMarginTop
        )
        panel.setFrameOrigin(origin)
    }

    /// Clicking another app resigns key; that is not an intentional
    /// dismissal, so the previous frontmost app is not restored here. (A
    /// file-importer sheet in flight is handled by `close(restoringPreviousApp:)`
    /// itself, not here — see its doc comment.)
    private func observeResignKey(for panel: NSPanel) {
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close(restoringPreviousApp: false)
            }
        }
    }
}
