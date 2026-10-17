import AppKit
import Combine
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

    /// Sees key presses before the responder chain does, so Up/Down/Return
    /// reach the option list whichever SwiftUI view happens to have focus.
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Tracks how many file importers are currently presented across the
/// wells. An `Int`, not a `Bool`, so that one well's transition settling
/// can't stomp on another's. `.fileImporter` shows `NSOpenPanel` as a sheet,
/// which resigns the panel's key status; without this guard,
/// `windowDidResignKey` would tear the panel down from underneath the open
/// dialog the moment a well is tapped.
@MainActor
final class QuickDropSession: ObservableObject {
    @Published var importerDepth = 0
    /// Dropped files waiting on the option list.
    @Published var pending: QuickDropPending?
    /// A drop landed on a well; a panel opened by a drag stays for it.
    var didReceiveDrop = false
    /// Set by `QuickDropView`, which owns the run.
    var onConfirm: ((QuickDropPending) -> Void)?

    /// A drop on a well. Tools without options run straight away.
    func offer(tool: NimbusTool, files: [URL]) {
        didReceiveDrop = true
        let choices = tool.choices
        pending = QuickDropPending(tool: tool, files: files, choices: choices, selection: tool.defaultChoiceIndex)
        if choices.isEmpty { confirm() }
    }

    func confirm() {
        guard let pending, let onConfirm else { return }
        onConfirm(pending)
    }

    /// For an offer made before the view had appeared to receive it.
    func flush() {
        if pending?.choices.isEmpty == true { confirm() }
    }

    /// Up/Down move the selection, Return runs it. Anything else is left alone.
    func handleKey(_ event: NSEvent) -> Bool {
        guard let pending, !pending.choices.isEmpty else { return false }
        switch event.keyCode {
        case 126: self.pending?.selection = max(0, pending.selection - 1)
        case 125: self.pending?.selection = min(pending.choices.count - 1, pending.selection + 1)
        case 36, 76: confirm()
        default: return false
        }
        return true
    }
}

/// Owns the panel's lifecycle so `AppDelegate` doesn't have to. The panel's
/// content — and its `QuickDropSession` — is rebuilt from scratch on every
/// open, so dropped-then-closed files never survive a close.
@MainActor
final class QuickDropPanelController {
    private var panel: QuickDropPanel?
    private var resignKeyObserver: NSObjectProtocol?
    private var session: QuickDropSession?
    private var previousFrontmostApp: NSRunningApplication?
    private var pendingObserver: AnyCancellable?
    private var dragMonitors: [Any] = []
    private var lastDragChange = 0
    private var openedByDrag = false

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

    /// Opens the panel by itself when files are dragged anywhere on screen, so
    /// there is already a well to drop them on. Global monitors see mouse
    /// events outside Nimbus without any permission; the drag pasteboard says
    /// whether the drag carries files.
    func startWatchingDrags() {
        guard dragMonitors.isEmpty else { return }
        lastDragChange = NSPasteboard(name: .drag).changeCount
        let handlers: [(NSEvent.EventTypeMask, @MainActor @Sendable () -> Void)] = [
            (.leftMouseDragged, { [weak self] in self?.dragMoved() }),
            (.leftMouseUp, { [weak self] in self?.mouseReleased() })
        ]
        for (mask, handler) in handlers {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in MainActor.assumeIsolated(handler) }) {
                dragMonitors.append(monitor)
            }
        }
    }

    private func dragMoved() {
        let pasteboard = NSPasteboard(name: .drag)
        // The pasteboard is filled in stages (a HEIC's file URL can land after
        // the first change), so a change is only spent once it has opened the
        // panel, and every drag event looks again.
        guard pasteboard.changeCount != lastDragChange, panel == nil,
              pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        else { return }
        lastDragChange = pasteboard.changeCount
        openedByDrag = true
        open(takeFocus: false)
    }

    /// A drag released without reaching a well: nothing was dropped, so the
    /// panel it opened goes away again. The global monitor can also see the
    /// release of a drop that lands on the panel itself, before the drop is
    /// handled, so closing waits a beat and spares a release over the panel.
    private func mouseReleased() {
        guard openedByDrag else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, self.openedByDrag, let panel = self.panel else { return }
            self.openedByDrag = false
            if self.session?.didReceiveDrop == false, !panel.frame.contains(NSEvent.mouseLocation) {
                self.close(restoringPreviousApp: false)
            }
        }
    }

    private func open(takeFocus: Bool = true) {
        previousFrontmostApp = NSWorkspace.shared.frontmostApplication

        let session = QuickDropSession()
        self.session = session
        // The option list needs the keyboard.
        pendingObserver = session.$pending.sink { [weak self] pending in
            if pending != nil { DispatchQueue.main.async { self?.panel?.makeKey() } }
        }

        let panel = makePanel(session: session)
        self.panel = panel
        let screenEdge = position(panel)
        observeResignKey(for: panel)

        // Slide the window itself, not the SwiftUI content: only `x` changes,
        // so the motion cannot pick up a vertical component from layout.
        if let screenEdge, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let final = panel.frame
            panel.setFrameOrigin(NSPoint(x: screenEdge, y: final.minY))
            show(panel, takeFocus: takeFocus)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(final, display: true)
            }
        } else {
            show(panel, takeFocus: takeFocus)
        }
        // The window shadow is cached from the alpha at first display; the card
        // fades and scales in, so recompute it once the content is on screen.
        panel.invalidateShadow()
    }

    /// A panel opened mid-drag must not take focus from the drag.
    private func show(_ panel: NSPanel, takeFocus: Bool) {
        if takeFocus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
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
        openedByDrag = false
        pendingObserver = nil
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
        // activating raises *every* window the app owns (Preferences
        // included), which would jump in front of whatever the user was working in. Such a panel
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
        // The system's own show animation zooms the window from its centre;
        // together with the slide in `QuickDropView` it read as a diagonal.
        panel.animationBehavior = .none
        // Never drawn — there is no titlebar — but VoiceOver announces it, and
        // the panel has no visible heading of its own.
        panel.title = String(localized: "Quick Drop", bundle: .l10n)

        // Escape backs out of the option list first, then closes the panel.
        panel.onCancel = { [weak self, weak session] in
            if session?.pending != nil {
                session?.pending = nil
            } else {
                self?.close(restoringPreviousApp: true)
            }
        }
        panel.keyHandler = { [weak session] event in
            MainActor.assumeIsolated { session?.handleKey(event) ?? false }
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

        // By default the hosting view resizes its window to follow the SwiftUI
        // content. The window is anchored by its bottom edge, so a resize after
        // the panel is shown moves the card vertically; size it once instead.
        // Wide enough for the widest state; the card hugs the right edge.
        let size = NSSize(
            width: QuickDropMetrics.expandedWidth + QuickDropMetrics.screenBleed + 2 * QuickDropMetrics.shadowMargin,
            height: hosting.fittingSize.height
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setContentSize(size)
        return panel
    }

    /// The screen under the cursor, falling back to `.main`. `visibleFrame`
    /// (not `frame`) is what makes the panel respect the menu bar and notch.
    /// The card sits against the right edge, centred vertically.
    /// Returns the right edge of that screen, where the slide-in starts.
    @discardableResult
    private func position(_ panel: NSPanel) -> CGFloat? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            return nil
        }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            // The card's right edge (inside the shadow margin) lands `screenBleed`
            // past the screen edge.
            x: screen.frame.maxX - size.width + QuickDropMetrics.shadowMargin + QuickDropMetrics.screenBleed,
            y: visible.midY - size.height / 2
        ))
        return screen.frame.maxX
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
