import Cocoa

/// Driftwall is free. A permanent "Support Driftwall…" item lives in the
/// menu and Settings; additionally, once the app has clearly been kept
/// around (a few launches in), we ask exactly once whether the user
/// wants to tip — with a "Don't ask again" checkbox. After that single
/// prompt it never asks again, regardless of the answer.
enum SupportPrompt {
    static let kofiURL = URL(string: "https://ko-fi.com/ets3d")!

    private static let suppressKey = "DriftwallSupportSuppressed"
    private static let launchCountKey = "DriftwallLaunchCount"
    private static let promptAfterLaunches = 5

    static func openKofi() {
        NSWorkspace.shared.open(kofiURL)
    }

    /// Call once per launch, after the UI is up. Increments the launch
    /// counter and shows the one-time tip prompt when the threshold is
    /// reached (never on first run).
    static func maybePromptOnLaunch() {
        let d = UserDefaults.standard
        let launches = d.integer(forKey: launchCountKey) + 1
        d.set(launches, forKey: launchCountKey)

        guard !d.bool(forKey: suppressKey),
              launches >= promptAfterLaunches else { return }

        // One-time: whatever the user does here, never ask again.
        d.set(true, forKey: suppressKey)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Enjoying Driftwall?"
        alert.informativeText = "Driftwall is free and made by one person. If it’s "
            + "brightening your desktop, a small tip on Ko-fi helps keep it going. "
            + "No pressure — this won’t ask again."
        alert.addButton(withTitle: "Buy Me a Coffee")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openKofi()
        }
    }
}
