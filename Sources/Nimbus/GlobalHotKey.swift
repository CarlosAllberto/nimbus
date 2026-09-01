import AppKit
import Carbon.HIToolbox
import Foundation

/// Fixed Quick Drop shortcut, ⌥⇧Q. A single constant, no capture UI this
/// round — see the Quick Drop plan. A global hot key wins over the frontmost
/// app's own menu shortcuts, so this deliberately avoids ⌘-based combinations
/// that apps commonly bind.
enum QuickDropShortcut {
    static let keyCode = UInt32(kVK_ANSI_Q)
    static let modifiers = UInt32(optionKey | shiftKey)

    /// The same combination expressed for an `NSMenuItem`.
    static let menuKeyEquivalent = "q"
    static let menuModifiers: NSEvent.ModifierFlags = [.option, .shift]
}

/// Spotlight shortcut, ⌘⇧Space. Deliberately avoids ⌘Space (the system
/// Spotlight) — the user explicitly asked for a modifier shift so the two
/// don't fight.
enum SpotlightShortcut {
    static let keyCode = UInt32(kVK_Space)
    static let modifiers = UInt32(cmdKey | shiftKey)

    /// The same combination expressed for an `NSMenuItem`.
    static let menuKeyEquivalent = " "
    static let menuModifiers: NSEvent.ModifierFlags = [.command, .shift]
}

/// Thin wrapper over Carbon's `RegisterEventHotKey`. Carbon is the right tool
/// here because, unlike `NSEvent.addGlobalMonitorForEvents`, it does not
/// require Accessibility permission — no privacy prompt for the user.
final class GlobalHotKey {
    // Touched only from the main thread: instances are only ever created
    // from `AppDelegate` (main actor), and Carbon delivers hot-key events on
    // the app's main run loop via `GetApplicationEventTarget()`. The C
    // callback below is a plain function pointer with no actor annotation,
    // so the compiler can't see that guarantee — hence `unsafe`.
    private static nonisolated(unsafe) var registeredHandlers: [UInt32: GlobalHotKey] = [:]
    private static nonisolated(unsafe) var nextID: UInt32 = 1
    private static nonisolated(unsafe) var isCarbonHandlerInstalled = false

    /// Arbitrary but stable 4-char signature ("QDR1") identifying our hot
    /// keys to Carbon; it never leaves this process.
    private static let signature: OSType = 0x51_44_52_31

    private let id: UInt32
    private let handler: () -> Void
    private var hotKeyRef: EventHotKeyRef?

    /// Fails (returns nil) if the combination already belongs to another
    /// process — `RegisterEventHotKey` fails silently otherwise. The caller
    /// must treat that as recoverable: log it and keep the menu item as the
    /// alternate path to the same feature.
    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.installCarbonHandlerIfNeeded()

        let id = Self.nextID
        Self.nextID += 1
        self.id = id
        self.handler = handler

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            NSLog("QuickDrop: RegisterEventHotKey failed with status %d", status)
            return nil
        }
        hotKeyRef = ref
        Self.registeredHandlers[id] = self
    }

    /// Explicit teardown. `registeredHandlers[id] = self` above is a strong
    /// reference back to this instance, so `deinit` can never run before
    /// something removes that entry — relying on `deinit` to do it is a
    /// permanent leak (and a stuck Carbon registration) waiting to happen.
    /// Call this before discarding a `GlobalHotKey` — e.g. `AppDelegate` at
    /// `applicationWillTerminate`, and a future "change shortcut" preference
    /// before registering the new combination.
    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
        Self.registeredHandlers[id] = nil
    }

    /// Backstop only: normal cleanup goes through `unregister()`, called
    /// explicitly. This just guards against `hotKeyRef` still being set if
    /// that was skipped, without touching the static registry (which, by
    /// definition, no longer holds this instance if deinit is running).
    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    /// The Carbon callback is a C function pointer and cannot capture
    /// context, so it looks the triggering instance up in a static registry
    /// keyed by `EventHotKeyID.id` and hops to the main queue before calling
    /// its handler.
    private static func installCarbonHandlerIfNeeded() {
        guard !isCarbonHandlerInstalled else { return }
        isCarbonHandlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let matchedID = hotKeyID.id
            DispatchQueue.main.async {
                GlobalHotKey.registeredHandlers[matchedID]?.handler()
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
