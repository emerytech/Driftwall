import Cocoa

/// Owns one wallpaper window per display, persists all settings, and
/// decides per-display whether to play based on independent inputs:
/// manual pause, battery, low-power mode, reduce-motion, occlusion.
/// Each display can also override the global source with its own
/// video or playlist folder.
final class WallpaperController {
    private var windows: [WallpaperWindow] = []
    private var views: [VideoWallpaperView] = []
    private var visible: [Bool] = []
    private var screenKeys: [String] = []

    private(set) var isPaused = false          // manual pause
    private var onBattery = false

    enum SourceMode: String { case single, playlist }
    struct DisplaySource: Codable { var kind: String; var path: String }  // kind: single|playlist

    enum Key {
        static let video = "DriftwallVideoURL"
        static let folder = "DriftwallPlaylistFolder"
        static let mode = "DriftwallSourceMode"
        static let fill = "DriftwallFill"
        static let speed = "DriftwallSpeed"
        static let muted = "DriftwallMuted"
        static let battery = "DriftwallPauseOnBattery"
        static let shuffle = "DriftwallShuffle"
        static let crossfade = "DriftwallCrossfade"
        static let clipMax = "DriftwallClipMax"
        static let lowPower = "DriftwallPauseLowPower"
        static let reduceMotion = "DriftwallRespectReduceMotion"
        static let fullscreen = "DriftwallPauseOnFullscreen"
        static let displays = "DriftwallDisplayMap"
    }

    private static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]

    var sourceMode: SourceMode {
        didSet {
            UserDefaults.standard.set(sourceMode.rawValue, forKey: Key.mode)
            applySourceToViews()
            updatePlayback()
        }
    }
    var pauseOnBattery: Bool {
        didSet { UserDefaults.standard.set(pauseOnBattery, forKey: Key.battery); updatePlayback() }
    }
    var pauseOnLowPower: Bool {
        didSet { UserDefaults.standard.set(pauseOnLowPower, forKey: Key.lowPower); updatePlayback() }
    }
    var respectReduceMotion: Bool {
        didSet { UserDefaults.standard.set(respectReduceMotion, forKey: Key.reduceMotion); updatePlayback() }
    }
    var pauseOnFullscreen: Bool {
        didSet { UserDefaults.standard.set(pauseOnFullscreen, forKey: Key.fullscreen); updatePlayback() }
    }
    var fill: Bool {
        didSet { UserDefaults.standard.set(fill, forKey: Key.fill); views.forEach { $0.fill = fill } }
    }
    var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: Key.speed); views.forEach { $0.rate = Float(speed) } }
    }
    var muted: Bool {
        didSet { UserDefaults.standard.set(muted, forKey: Key.muted); views.forEach { $0.muted = muted } }
    }
    var shuffle: Bool {
        didSet {
            UserDefaults.standard.set(shuffle, forKey: Key.shuffle)
            applySourceToViews(); updatePlayback()
        }
    }
    var crossfade: Double {
        didSet {
            UserDefaults.standard.set(crossfade, forKey: Key.crossfade)
            views.forEach { $0.crossfade = crossfade }
        }
    }
    var clipMax: Double {
        didSet {
            UserDefaults.standard.set(clipMax, forKey: Key.clipMax)
            views.forEach { $0.maxClip = clipMax }
        }
    }

    private var currentURL: URL?
    private var playlistFolder: URL?
    private var displayMap: [String: DisplaySource] = [:]
    private let power = PowerMonitor()
    private let fullscreen = FullscreenMonitor()
    private var fullscreenCovered = false

    var videoURL: URL? { currentURL }
    var folderURL: URL? { playlistFolder }
    var hasVideo: Bool {
        sourceMode == .single ? resolvedSingleURL() != nil : !videoFiles(in: playlistFolder).isEmpty
    }

    var playlistSummary: String {
        guard let f = playlistFolder else { return "No folder selected" }
        return "\(f.path) — \(videoFiles(in: f).count) video(s)"
    }

    init() {
        let d = UserDefaults.standard
        sourceMode = SourceMode(rawValue: d.string(forKey: Key.mode) ?? "single") ?? .single
        pauseOnBattery = d.bool(forKey: Key.battery)
        pauseOnLowPower = d.bool(forKey: Key.lowPower)
        respectReduceMotion = d.bool(forKey: Key.reduceMotion)
        pauseOnFullscreen = d.bool(forKey: Key.fullscreen)
        fill = d.bool(forKey: Key.fill)
        speed = d.double(forKey: Key.speed)
        muted = d.bool(forKey: Key.muted)
        shuffle = d.bool(forKey: Key.shuffle)
        crossfade = d.double(forKey: Key.crossfade)
        clipMax = d.double(forKey: Key.clipMax)
        if let data = d.data(forKey: Key.displays),
           let m = try? JSONDecoder().decode([String: DisplaySource].self, from: data) {
            displayMap = m
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(envChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(envChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    func start() {
        let d = UserDefaults.standard
        currentURL = d.url(forKey: Key.video)
        playlistFolder = d.url(forKey: Key.folder)

        rebuildWindows()
        onBattery = power.isOnBattery
        power.onChange = { [weak self] battery in
            self?.onBattery = battery
            self?.updatePlayback()
        }
        power.start()
        fullscreen.onChange = { [weak self] covered in
            self?.fullscreenCovered = covered
            self?.updatePlayback()
        }
        fullscreen.start()
        applySourceToViews()
        updatePlayback()
    }

    func setVideo(url: URL) {
        currentURL = url
        UserDefaults.standard.set(url, forKey: Key.video)
        sourceMode = .single   // didSet re-applies + updates playback
    }

    func setPlaylistFolder(_ url: URL) {
        playlistFolder = url
        UserDefaults.standard.set(url, forKey: Key.folder)
        sourceMode = .playlist
    }

    func togglePause() {
        isPaused.toggle()
        updatePlayback()
    }

    // MARK: Per-display configuration

    func connectedDisplays() -> [String] { NSScreen.screens.map(screenKey) }

    func displayConfig(for key: String) -> DisplaySource? { displayMap[key] }

    func setDisplayVideo(_ key: String, url: URL) {
        displayMap[key] = DisplaySource(kind: "single", path: url.path)
        persistDisplayMap(); applySourceToViews(); updatePlayback()
    }

    func setDisplayFolder(_ key: String, url: URL) {
        displayMap[key] = DisplaySource(kind: "playlist", path: url.path)
        persistDisplayMap(); applySourceToViews(); updatePlayback()
    }

    func clearDisplay(_ key: String) {
        displayMap[key] = nil
        persistDisplayMap(); applySourceToViews(); updatePlayback()
    }

    private func persistDisplayMap() {
        if let data = try? JSONEncoder().encode(displayMap) {
            UserDefaults.standard.set(data, forKey: Key.displays)
        }
    }

    private func screenKey(_ s: NSScreen) -> String { s.localizedName }

    // MARK: Source resolution

    private func resolvedSingleURL() -> URL? {
        let fm = FileManager.default
        if let u = currentURL, fm.fileExists(atPath: u.path) { return u }
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Wallpapers")
        let aerial = dir.appendingPathComponent("aerial.mp4")
        if fm.fileExists(atPath: aerial.path) { return aerial }
        return videoFiles(in: dir).sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }.first
    }

    private func videoFiles(in folder: URL?) -> [URL] {
        guard let folder,
              let items = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        return items
            .filter { Self.videoExts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func loadGlobal(into view: VideoWallpaperView) {
        switch sourceMode {
        case .single:
            guard let url = resolvedSingleURL() else { return }
            if url != currentURL {
                currentURL = url
                UserDefaults.standard.set(url, forKey: Key.video)
            }
            view.loadSingle(url: url)
        case .playlist:
            var urls = videoFiles(in: playlistFolder)
            guard !urls.isEmpty else { return }
            if shuffle { urls.shuffle() }
            view.loadPlaylist(urls)
        }
    }

    private func applySourceToViews() {
        for (i, view) in views.enumerated() {
            let key = i < screenKeys.count ? screenKeys[i] : ""
            guard let cfg = displayMap[key] else { loadGlobal(into: view); continue }
            let url = URL(fileURLWithPath: cfg.path)
            if cfg.kind == "playlist" {
                var urls = videoFiles(in: url)
                if shuffle { urls.shuffle() }
                if !urls.isEmpty { view.loadPlaylist(urls) } else { loadGlobal(into: view) }
            } else if FileManager.default.fileExists(atPath: cfg.path) {
                view.loadSingle(url: url)
            } else {
                loadGlobal(into: view)   // per-display file went missing
            }
        }
    }

    private func updatePlayback() {
        let batteryBlocked = pauseOnBattery && onBattery
        let lowPowerBlocked = pauseOnLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled
        let reduceMotionBlocked = respectReduceMotion
            && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fullscreenBlocked = pauseOnFullscreen && fullscreenCovered
        let blocked = isPaused || batteryBlocked || lowPowerBlocked
            || reduceMotionBlocked || fullscreenBlocked
        for (i, view) in views.enumerated() {
            (!blocked && visible[i]) ? view.play() : view.pause()
        }
    }

    @objc private func envChanged() { updatePlayback() }

    @objc private func screensChanged() {
        rebuildWindows()
        applySourceToViews()
        updatePlayback()
    }

    @objc private func occlusionChanged(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              let idx = windows.firstIndex(where: { $0 === window })
        else { return }
        visible[idx] = window.occlusionState.contains(.visible)
        updatePlayback()
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        visible.removeAll()
        screenKeys.removeAll()
        for screen in NSScreen.screens {
            let window = WallpaperWindow(screen: screen)
            let view = VideoWallpaperView(
                frame: NSRect(origin: .zero, size: screen.frame.size))
            view.autoresizingMask = [.width, .height]
            view.fill = fill
            view.muted = muted
            view.rate = Float(speed)
            view.crossfade = crossfade
            view.maxClip = clipMax
            window.contentView = view
            window.orderFront(nil)
            windows.append(window)
            views.append(view)
            visible.append(true)
            screenKeys.append(screenKey(screen))
        }
    }
}
