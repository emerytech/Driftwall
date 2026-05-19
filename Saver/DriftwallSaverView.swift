import ScreenSaver
import AVFoundation
import AppKit

/// Screen-saver companion. macOS runs screen savers at the lock screen
/// and login window, so this is how Driftwall reaches those surfaces
/// (a session app cannot draw there directly).
///
/// It tries to mirror the app's chosen video by reading the app's
/// preferences domain; failing that (the modern screensaver host is
/// sandboxed, so cross-domain reads can be denied) it falls back to
/// ~/Wallpapers/aerial.mp4 or the newest clip there.
@objc(DriftwallSaverView)
final class DriftwallSaverView: ScreenSaverView {
    private let playerLayer = AVPlayerLayer()
    private var queue: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        playerLayer.frame = bounds
        root.addSublayer(playerLayer)
        configure()
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func appDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.local.driftwall") ?? .standard
    }

    private func resolveVideo() -> URL? {
        let fm = FileManager.default
        let d = appDefaults()
        if let u = d.url(forKey: "DriftwallVideoURL"), fm.fileExists(atPath: u.path) {
            return u
        }
        if let s = d.string(forKey: "DriftwallVideoURL") {
            let u = URL(fileURLWithPath: s)
            if fm.fileExists(atPath: u.path) { return u }
        }
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Wallpapers")
        let aerial = dir.appendingPathComponent("aerial.mp4")
        if fm.fileExists(atPath: aerial.path) { return aerial }
        let exts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]
        let vids = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return vids
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
            .first
    }

    private func configure() {
        let d = appDefaults()
        let fill = (d.object(forKey: "DriftwallFill") as? Bool) ?? true
        let muted = (d.object(forKey: "DriftwallMuted") as? Bool) ?? true
        playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        guard let url = resolveVideo() else { return }
        let qp = AVQueuePlayer()
        qp.isMuted = muted
        looper = AVPlayerLooper(player: qp, templateItem: AVPlayerItem(url: url))
        queue = qp
        playerLayer.player = qp
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    override func startAnimation() {
        super.startAnimation()
        queue?.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        queue?.pause()
    }

    override func animateOneFrame() {}   // AVPlayer drives rendering

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
