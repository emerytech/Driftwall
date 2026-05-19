import AppKit
import AVFoundation

/// Sets the macOS desktop picture to a still frame of the current video.
/// The lock screen shows the desktop picture, so this makes locking read
/// as "the video, paused" — fluid until the screen saver kicks in.
/// Restores the wallpaper it replaced when turned off.
enum LockScreenMatch {
    private static let savedKey = "DriftwallSavedWallpaper"

    private static var dir: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Driftwall")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func set(enabled: Bool, video: URL?) {
        if enabled {
            saveOriginalIfNeeded()
            refresh(video: video, enabled: true)
        } else if let orig = UserDefaults.standard.string(forKey: savedKey) {
            setWallpaper(URL(fileURLWithPath: orig))
            UserDefaults.standard.removeObject(forKey: savedKey)
        }
    }

    /// Re-grab when the chosen video changes (no-op unless enabled).
    static func refresh(video: URL?, enabled: Bool) {
        guard enabled, let video, let data = frameJPEG(from: video) else { return }
        // Unique filename each time — macOS caches the desktop picture by
        // path, so reusing one wouldn't visibly update.
        let new = dir.appendingPathComponent("lockscreen-\(Int(Date().timeIntervalSince1970)).jpg")
        guard (try? data.write(to: new)) != nil else { return }
        setWallpaper(new)
        // Clean older frames.
        let stale = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in stale where f.lastPathComponent.hasPrefix("lockscreen-") && f != new {
            try? FileManager.default.removeItem(at: f)
        }
    }

    private static func saveOriginalIfNeeded() {
        let d = UserDefaults.standard
        guard d.string(forKey: savedKey) == nil,
              let screen = NSScreen.main ?? NSScreen.screens.first,
              let cur = NSWorkspace.shared.desktopImageURL(for: screen)
        else { return }
        d.set(cur.path, forKey: savedKey)
    }

    private static func setWallpaper(_ url: URL) {
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    private static func frameJPEG(from video: URL) -> Data? {
        let asset = AVURLAsset(url: video)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let dur = CMTimeGetSeconds(asset.duration)
        let secs = (dur.isFinite && dur > 0) ? dur * 0.25 : 0
        let t = CMTime(seconds: secs, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: t, actualTime: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}
