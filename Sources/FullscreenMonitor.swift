import Cocoa

/// Reports when the main display is fully covered by another app — a
/// native-fullscreen app, a game, or any window spanning the whole
/// screen. The wallpaper window joins all Spaces (so it shows on every
/// desktop), which means macOS occlusion does *not* reliably pause it
/// behind a fullscreen Space — this fills that gap so we stop decoding
/// video nobody can see.
final class FullscreenMonitor {
    var onChange: ((_ covered: Bool) -> Void)?
    private(set) var isCovered = false
    private var timer: Timer?

    func start() {
        let wsnc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didDeactivateApplicationNotification] {
            wsnc.addObserver(self, selector: #selector(reevaluate),
                             name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(reevaluate),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Games can enter/exit fullscreen without an app-activation event,
        // so a slow timer is a cheap safety net (one tiny window-list query).
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.reevaluate()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        reevaluate()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        timer = nil
    }

    @objc private func reevaluate() {
        let covered = Self.mainDisplayIsCovered()
        if covered != isCovered {
            isCovered = covered
            onChange?(covered)
        }
    }

    /// True if a normal-level window owned by another process spans the
    /// entire main display (CG coordinates — no AppKit flip needed since
    /// `CGDisplayBounds` and window bounds share the same space).
    private static func mainDisplayIsCovered() -> Bool {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let screen = CGDisplayBounds(CGMainDisplayID())
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }

        for info in infos {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  Int32(pid) != myPID,
                  let bounds = info[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary)
            else { continue }

            // Covers the whole main display (1pt tolerance for rounding).
            if rect.minX <= screen.minX + 1, rect.minY <= screen.minY + 1,
               rect.maxX >= screen.maxX - 1, rect.maxY >= screen.maxY - 1 {
                return true
            }
        }
        return false
    }
}
