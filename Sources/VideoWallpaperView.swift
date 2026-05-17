import Cocoa
import AVFoundation

/// Two stacked player layers. Single mode = one gapless looping clip.
/// Playlist mode = cycle a list, opacity-crossfading between clips.
final class VideoWallpaperView: NSView {
    private let layerA = AVPlayerLayer()
    private let layerB = AVPlayerLayer()
    private var playerA: AVQueuePlayer?
    private var playerB: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    private var playing = false
    private var isPlaylist = false
    private var playlist: [URL] = []
    private var index = 0
    private var frontIsA = true
    private var transitioning = false

    private var timeObserver: Any?
    private var observedPlayer: AVQueuePlayer?

    var crossfade: Double = 1.5
    var maxClip: Double = 0          // 0 = play each clip in full

    var fill = true { didSet { applyGravity() } }
    var muted = true { didSet { playerA?.isMuted = muted; playerB?.isMuted = muted } }
    var rate: Float = 1 { didSet { if playing { frontPlayer()?.rate = rate } } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        for l in [layerA, layerB] {
            l.videoGravity = .resizeAspectFill
            l.frame = bounds
            root.addSublayer(l)
        }
        layerB.opacity = 0
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        layerA.frame = bounds
        layerB.frame = bounds
    }

    private func frontPlayer() -> AVQueuePlayer? { frontIsA ? playerA : playerB }

    private func applyGravity() {
        let g: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
        layerA.videoGravity = g
        layerB.videoGravity = g
    }

    // MARK: Single

    func loadSingle(url: URL) {
        teardown()
        isPlaylist = false
        let p = AVQueuePlayer()
        p.isMuted = muted
        looper = AVPlayerLooper(player: p, templateItem: AVPlayerItem(url: url))
        playerA = p
        layerA.player = p
        frontIsA = true
        layerA.opacity = 1
        layerB.opacity = 0
        if playing { p.rate = rate }
    }

    // MARK: Playlist

    func loadPlaylist(_ urls: [URL]) {
        teardown()
        guard !urls.isEmpty else { return }
        isPlaylist = true
        playlist = urls
        index = 0
        frontIsA = true
        layerA.opacity = 1
        layerB.opacity = 0
        let p = makePlayer(urls[0])
        playerA = p
        layerA.player = p
        if playing { p.rate = rate }
        addObserverToFront()
    }

    private func makePlayer(_ url: URL) -> AVQueuePlayer {
        let p = AVQueuePlayer(items: [AVPlayerItem(url: url)])
        p.isMuted = muted
        p.actionAtItemEnd = .pause
        return p
    }

    private func addObserverToFront() {
        removeObserver()
        guard let p = frontPlayer() else { return }
        observedPlayer = p
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main) { [weak self] _ in self?.tick() }
    }

    private func removeObserver() {
        if let t = timeObserver, let p = observedPlayer { p.removeTimeObserver(t) }
        timeObserver = nil
        observedPlayer = nil
    }

    private func tick() {
        guard isPlaylist, playing, !transitioning,
              let p = frontPlayer(),
              let item = p.currentItem,
              item.duration.isNumeric else { return }
        let dur = item.duration.seconds
        let now = p.currentTime().seconds
        let nearEnd = dur > 0 && dur - now <= crossfade
        // Rotate long clips early so a playlist keeps moving.
        let hitCap = maxClip > 0 && now >= max(crossfade, maxClip - crossfade)
        if nearEnd || hitCap { advance() }
    }

    private func advance() {
        guard playlist.count > 0 else { return }
        transitioning = true
        let next = (index + 1) % playlist.count
        let nextOnA = !frontIsA

        let incoming = makePlayer(playlist[next])
        if nextOnA { playerB = incoming; layerB.player = incoming }
        else { playerA = incoming; layerA.player = incoming }
        incoming.seek(to: .zero)
        if playing { incoming.rate = rate }

        let inLayer = nextOnA ? layerB : layerA
        let outLayer = nextOnA ? layerA : layerB

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.duration = crossfade

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.removeObserver()                       // detach from old front (still alive)
            if self.frontIsA {
                self.playerA?.pause(); self.playerA = nil; self.layerA.player = nil
            } else {
                self.playerB?.pause(); self.playerB = nil; self.layerB.player = nil
            }
            self.frontIsA = nextOnA
            self.index = next
            self.transitioning = false
            self.addObserverToFront()
        }
        inLayer.opacity = 1
        outLayer.opacity = 0
        inLayer.add(fade, forKey: "opacity")
        outLayer.add(fade, forKey: "opacity")
        CATransaction.commit()
    }

    // MARK: Transport

    func play() {
        playing = true
        if transitioning { playerA?.rate = rate; playerB?.rate = rate }
        else { frontPlayer()?.rate = rate }
    }

    func pause() {
        playing = false
        playerA?.pause()
        playerB?.pause()
    }

    private func teardown() {
        removeObserver()
        playerA?.pause()
        playerB?.pause()
        playerA = nil
        playerB = nil
        looper = nil
        layerA.player = nil
        layerB.player = nil
        playlist = []
        index = 0
        transitioning = false
    }
}
