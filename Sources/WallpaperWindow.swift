import Cocoa

/// A borderless, click-through window pinned to the desktop layer:
/// above the system wallpaper, below the desktop icons, on every Space.
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        // Clicks fall through to Finder / the desktop.
        ignoresMouseEvents = true
        // Sit at the desktop level (behind icons, in front of the wallpaper).
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
