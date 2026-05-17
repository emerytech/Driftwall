import Cocoa

/// One-time warning shown when the user turns *off* "Pause on battery".
/// With the protection disabled, video wallpaper keeps playing on battery
/// power and drains it noticeably faster — so we say so once, with a
/// "Don't show again" checkbox.
enum BatteryWarning {
    private static let suppressKey = "DriftwallBatteryWarningSuppressed"

    /// Call after pause-on-battery has just been disabled by the user.
    static func showAfterDisable() {
        guard !UserDefaults.standard.bool(forKey: suppressKey) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Battery may drain faster"
        alert.informativeText = "With “Pause on battery” turned off, Driftwall keeps "
            + "playing video wallpaper while running on battery. Video playback uses "
            + "the GPU continuously and can drain your battery noticeably faster."
        alert.addButton(withTitle: "OK")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t show this again"

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()

        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressKey)
        }
    }
}
