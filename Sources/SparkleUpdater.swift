import AppKit
import Sparkle

/// Sparkle-backed auto-updater. `SPUStandardUpdaterController` with
/// `startingUpdater: true` handles scheduled background checks itself
/// (per SUScheduledCheckInterval / SUAutomaticallyChecksForUpdates in
/// Info.plist); the menu item triggers a manual check.
final class SparkleUpdater {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
