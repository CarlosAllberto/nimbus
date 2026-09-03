import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` — registers/unregisters *this*
/// app bundle as a login item directly, no separate helper tool or agent
/// target needed (that's only required for `SMAppService.agent`/`.daemon`).
/// No extra entitlement either: that's a `SMJobBless`-era requirement this
/// API doesn't share.
enum LaunchAtLogin {
    /// Read fresh every time rather than cached: the user can toggle this
    /// from System Settings > General > Login Items directly, outside the
    /// app entirely, and this must reflect that.
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// `register()`/`unregister()` both throw only for conditions outside
    /// the user's control here (sandboxing/bundle-location issues) — there
    /// is no local recovery, so this just drops the error rather than
    /// surfacing a dead-end alert. The caller re-reads `status` afterward,
    /// which is what actually reflects whether it took.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LaunchAtLogin: %@ failed: %@", enabled ? "register" : "unregister", error.localizedDescription)
        }
    }

    /// macOS can register the login item but hold it pending the user's own
    /// approval in System Settings — `.requiresApproval` is that state, and
    /// the toggle alone can't finish the job from here.
    static let loginItemsSettingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
}
