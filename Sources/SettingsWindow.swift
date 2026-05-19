import Cocoa
import UniformTypeIdentifiers
import ServiceManagement

/// A real titled window so the app is manageable without hunting for the
/// menu-bar icon (which hides behind the notch). Re-launching the app
/// brings this to the front via applicationShouldHandleReopen.
final class SettingsWindowController: NSWindowController {
    private let controller: WallpaperController

    // Wired up by AppDelegate (it owns the status item).
    var menuBarIsOn: () -> Bool = { true }
    var setMenuBarVisible: (Bool) -> Void = { _ in }

    private let pathLabel = NSTextField(labelWithString: "")
    private let speedLabel = NSTextField(labelWithString: "1.00×")
    private let speedSlider = NSSlider(value: 1, minValue: 0.25, maxValue: 2,
                                       target: nil, action: nil)
    private let fillCheck = NSButton(checkboxWithTitle: "Fill screen (uncheck to fit / letterbox)",
                                     target: nil, action: nil)
    private let muteCheck = NSButton(checkboxWithTitle: "Mute audio", target: nil, action: nil)
    private let shuffleCheck = NSButton(checkboxWithTitle: "Shuffle playlist", target: nil, action: nil)
    private let crossfadeLabel = NSTextField(labelWithString: "1.5s")
    private let crossfadeSlider = NSSlider(value: 1.5, minValue: 0.25, maxValue: 5,
                                           target: nil, action: nil)
    private let clipMaxLabel = NSTextField(labelWithString: "Full")
    private let clipMaxSlider = NSSlider(value: 0, minValue: 0, maxValue: 60,
                                         target: nil, action: nil)
    private let pauseCheck = NSButton(checkboxWithTitle: "Pause", target: nil, action: nil)
    private let batteryCheck = NSButton(checkboxWithTitle: "Pause on battery", target: nil, action: nil)
    private let lowPowerCheck = NSButton(checkboxWithTitle: "Pause in Low Power Mode", target: nil, action: nil)
    private let reduceMotionCheck = NSButton(checkboxWithTitle: "Respect Reduce Motion", target: nil, action: nil)
    private let fullscreenCheck = NSButton(checkboxWithTitle: "Pause when an app is fullscreen", target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let menuBarCheck = NSButton(checkboxWithTitle: "Show menu-bar icon", target: nil, action: nil)
    private let appearanceControl = NSSegmentedControl(
        labels: ["Glass", "Classic"], trackingMode: .selectOne, target: nil, action: nil)

    private let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let folderLabel = NSTextField(labelWithString: "")
    private let apiKeyField = NSSecureTextField()
    private let coverrKeyField = NSSecureTextField()
    private let pixabayKeyField = NSSecureTextField()
    private let stockBrowser = StockBrowserWindowController()
    private var library: LibraryWindowController!
    private var displayConfig: DisplayConfigWindowController!
    private var scheduleConfig: ScheduleWindowController!
    private static let pexelsKeyDefault = "DriftwallPexelsKey"
    private static let coverrKeyDefault = "DriftwallCoverrKey"
    private static let pixabayKeyDefault = "DriftwallPixabayKey"

    private var progressSheet: NSWindow?
    private let progressBar = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")

    init(controller: WallpaperController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Driftwall"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 460, height: 360)
        super.init(window: window)
        library = LibraryWindowController(controller: controller)
        library.onChange = { [weak self] in self?.refresh() }
        displayConfig = DisplayConfigWindowController(controller: controller)
        displayConfig.onChange = { [weak self] in self?.refresh() }
        scheduleConfig = ScheduleWindowController(controller: controller)
        scheduleConfig.onChange = { [weak self] in self?.refresh() }
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        // The control list is taller than the window on smaller screens, so
        // host it in a scroll view — otherwise the bottom rows (Appearance,
        // Quit) end up hidden behind the Dock and are unreachable.
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        content.addSubview(scroll)

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            // Document width tracks the viewport (vertical scrolling only);
            // its height is driven by the stack via the constants below.
            doc.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            doc.topAnchor.constraint(equalTo: clip.topAnchor),
            doc.widthAnchor.constraint(equalTo: clip.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -20),
        ])

        // Header: app icon + name + version.
        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        if let icon = NSApp.applicationIconImage {
            let iv = NSImageView(image: icon)
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 56).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 56).isActive = true
            header.addArrangedSubview(iv)
        }
        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2
        let name = NSTextField(labelWithString: "Driftwall")
        name.font = .systemFont(ofSize: 20, weight: .semibold)
        let version = NSTextField(labelWithString: "Version \(appVersion())")
        version.textColor = .secondaryLabelColor
        version.font = .systemFont(ofSize: 11)
        titleStack.addArrangedSubview(name)
        titleStack.addArrangedSubview(version)
        header.addArrangedSubview(titleStack)
        stack.addArrangedSubview(header)

        stack.addArrangedSubview(separator())

        let heading = NSTextField(labelWithString: "Wallpaper video")
        heading.font = .boldSystemFont(ofSize: 13)
        stack.addArrangedSubview(heading)

        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.widthAnchor.constraint(equalToConstant: 420).isActive = true
        stack.addArrangedSubview(pathLabel)

        let videoButtons = NSStackView()
        videoButtons.orientation = .horizontal
        videoButtons.spacing = 8
        videoButtons.addArrangedSubview(
            NSButton(title: "Choose Video…", target: self, action: #selector(chooseVideo)))
        videoButtons.addArrangedSubview(
            NSButton(title: "Add from URL…", target: self, action: #selector(addFromURL)))
        videoButtons.addArrangedSubview(
            NSButton(title: "Video Library…", target: self, action: #selector(openLibrary)))
        videoButtons.addArrangedSubview(
            NSButton(title: "Reveal in Finder", target: self, action: #selector(revealVideo)))
        stack.addArrangedSubview(videoButtons)

        stack.addArrangedSubview(separator())

        // Source mode.
        let sourceHeading = NSTextField(labelWithString: "Source")
        sourceHeading.font = .boldSystemFont(ofSize: 13)
        stack.addArrangedSubview(sourceHeading)

        sourcePopup.addItems(withTitles: [
            "Single video", "Playlist folder (crossfade)", "Scheduled (time of day)"])
        sourcePopup.target = self
        sourcePopup.action = #selector(sourceChanged)
        stack.addArrangedSubview(sourcePopup)

        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.maximumNumberOfLines = 1
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        folderLabel.widthAnchor.constraint(equalToConstant: 440).isActive = true
        stack.addArrangedSubview(folderLabel)

        let sourceButtons = NSStackView()
        sourceButtons.orientation = .horizontal
        sourceButtons.spacing = 8
        sourceButtons.addArrangedSubview(
            NSButton(title: "Choose Folder…", target: self, action: #selector(chooseFolder)))
        sourceButtons.addArrangedSubview(
            NSButton(title: "Displays…", target: self, action: #selector(openDisplays)))
        sourceButtons.addArrangedSubview(
            NSButton(title: "Schedule…", target: self, action: #selector(openSchedule)))
        sourceButtons.addArrangedSubview(
            NSButton(title: "Browse Stock…", target: self, action: #selector(openStock)))
        stack.addArrangedSubview(sourceButtons)

        let keyRow = NSStackView()
        keyRow.orientation = .horizontal
        keyRow.alignment = .centerY
        keyRow.spacing = 8
        let keyTitle = NSTextField(labelWithString: "Pexels key")
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        apiKeyField.placeholderString = "free at pexels.com/api"
        keyRow.addArrangedSubview(keyTitle)
        keyRow.addArrangedSubview(apiKeyField)
        keyRow.addArrangedSubview(
            NSButton(title: "Save Keys", target: self, action: #selector(saveKey)))
        stack.addArrangedSubview(keyRow)

        let coverrRow = NSStackView()
        coverrRow.orientation = .horizontal
        coverrRow.alignment = .centerY
        coverrRow.spacing = 8
        let coverrTitle = NSTextField(labelWithString: "Coverr key")
        coverrKeyField.translatesAutoresizingMaskIntoConstraints = false
        coverrKeyField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        coverrKeyField.placeholderString = "free at coverr.co/api"
        coverrRow.addArrangedSubview(coverrTitle)
        coverrRow.addArrangedSubview(coverrKeyField)
        stack.addArrangedSubview(coverrRow)

        let pixabayRow = NSStackView()
        pixabayRow.orientation = .horizontal
        pixabayRow.alignment = .centerY
        pixabayRow.spacing = 8
        let pixabayTitle = NSTextField(labelWithString: "Pixabay key")
        pixabayKeyField.translatesAutoresizingMaskIntoConstraints = false
        pixabayKeyField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        pixabayKeyField.placeholderString = "free at pixabay.com/api/docs"
        pixabayRow.addArrangedSubview(pixabayTitle)
        pixabayRow.addArrangedSubview(pixabayKeyField)
        stack.addArrangedSubview(pixabayRow)

        stockBrowser.keyFor = { src in
            let key: String
            switch src {
            case .pexels:  key = Self.pexelsKeyDefault
            case .coverr:  key = Self.coverrKeyDefault
            case .pixabay: key = Self.pixabayKeyDefault
            }
            return UserDefaults.standard.string(forKey: key) ?? ""
        }
        stockBrowser.onPick = { [weak self] url in self?.downloadAndUse(url) }

        stack.addArrangedSubview(separator())

        // Playback.
        let playbackHeading = NSTextField(labelWithString: "Playback")
        playbackHeading.font = .boldSystemFont(ofSize: 13)
        stack.addArrangedSubview(playbackHeading)

        fillCheck.target = self
        fillCheck.action = #selector(toggleFill)
        stack.addArrangedSubview(fillCheck)

        muteCheck.target = self
        muteCheck.action = #selector(toggleMute)
        stack.addArrangedSubview(muteCheck)

        let speedRow = NSStackView()
        speedRow.orientation = .horizontal
        speedRow.alignment = .centerY
        speedRow.spacing = 10
        let speedTitle = NSTextField(labelWithString: "Speed")
        speedSlider.target = self
        speedSlider.action = #selector(speedChanged)
        speedSlider.isContinuous = true
        speedSlider.translatesAutoresizingMaskIntoConstraints = false
        speedSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        speedLabel.textColor = .secondaryLabelColor
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        speedRow.addArrangedSubview(speedTitle)
        speedRow.addArrangedSubview(speedSlider)
        speedRow.addArrangedSubview(speedLabel)
        stack.addArrangedSubview(speedRow)

        shuffleCheck.target = self
        shuffleCheck.action = #selector(toggleShuffle)
        stack.addArrangedSubview(shuffleCheck)

        stack.addArrangedSubview(sliderRow(
            "Crossfade", crossfadeSlider, crossfadeLabel, #selector(crossfadeChanged)))
        stack.addArrangedSubview(sliderRow(
            "Max clip", clipMaxSlider, clipMaxLabel, #selector(clipMaxChanged)))

        stack.addArrangedSubview(separator())

        // Power / behavior.
        let behaviorHeading = NSTextField(labelWithString: "Behavior")
        behaviorHeading.font = .boldSystemFont(ofSize: 13)
        stack.addArrangedSubview(behaviorHeading)

        for (box, sel) in [(pauseCheck, #selector(togglePause)),
                           (batteryCheck, #selector(toggleBattery)),
                           (lowPowerCheck, #selector(toggleLowPower)),
                           (fullscreenCheck, #selector(toggleFullscreen)),
                           (reduceMotionCheck, #selector(toggleReduceMotion)),
                           (loginCheck, #selector(toggleLogin)),
                           (menuBarCheck, #selector(toggleMenuBar))] {
            box.target = self
            box.action = sel
            stack.addArrangedSubview(box)
        }

        let appearanceRow = NSStackView()
        appearanceRow.orientation = .horizontal
        appearanceRow.alignment = .centerY
        appearanceRow.spacing = 10
        appearanceRow.addArrangedSubview(NSTextField(labelWithString: "Appearance"))
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged)
        appearanceRow.addArrangedSubview(appearanceControl)
        stack.addArrangedSubview(appearanceRow)

        stack.addArrangedSubview(
            NSButton(title: "Set Up Lock Screen…",
                     target: self, action: #selector(setUpLockScreen)))

        stack.addArrangedSubview(separator())

        let bottom = NSStackView()
        bottom.orientation = .horizontal
        bottom.spacing = 8
        bottom.addArrangedSubview(NSButton(title: "Support Driftwall…",
            target: self, action: #selector(openSupport)))
        let quit = NSButton(title: "Quit Driftwall",
                            target: NSApp, action: #selector(NSApplication.terminate(_:)))
        bottom.addArrangedSubview(quit)
        stack.addArrangedSubview(bottom)
    }

    @objc private func openSupport() { SupportPrompt.openKofi() }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return box
    }

    private func sliderRow(_ title: String, _ slider: NSSlider,
                           _ valueLabel: NSTextField, _ action: Selector) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        slider.target = self
        slider.action = action
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 210).isActive = true
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let t = NSTextField(labelWithString: title)
        t.translatesAutoresizingMaskIntoConstraints = false
        t.widthAnchor.constraint(equalToConstant: 82).isActive = true
        row.addArrangedSubview(t)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func appVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    func refresh() {
        pathLabel.stringValue = controller.videoURL?.path ?? "None selected"
        switch controller.sourceMode {
        case .single:   sourcePopup.selectItem(at: 0)
        case .playlist: sourcePopup.selectItem(at: 1)
        case .schedule: sourcePopup.selectItem(at: 2)
        }
        folderLabel.stringValue = controller.playlistSummary
        apiKeyField.stringValue = UserDefaults.standard.string(forKey: Self.pexelsKeyDefault) ?? ""
        coverrKeyField.stringValue = UserDefaults.standard.string(forKey: Self.coverrKeyDefault) ?? ""
        pixabayKeyField.stringValue = UserDefaults.standard.string(forKey: Self.pixabayKeyDefault) ?? ""
        fillCheck.state = controller.fill ? .on : .off
        muteCheck.state = controller.muted ? .on : .off
        speedSlider.doubleValue = controller.speed
        speedLabel.stringValue = String(format: "%.2f×", controller.speed)
        shuffleCheck.state = controller.shuffle ? .on : .off
        crossfadeSlider.doubleValue = controller.crossfade
        crossfadeLabel.stringValue = String(format: "%.1fs", controller.crossfade)
        clipMaxSlider.doubleValue = controller.clipMax
        clipMaxLabel.stringValue = controller.clipMax < 1 ? "Full" : "\(Int(controller.clipMax))s"
        pauseCheck.state = controller.isPaused ? .on : .off
        batteryCheck.state = controller.pauseOnBattery ? .on : .off
        lowPowerCheck.state = controller.pauseOnLowPower ? .on : .off
        reduceMotionCheck.state = controller.respectReduceMotion ? .on : .off
        fullscreenCheck.state = controller.pauseOnFullscreen ? .on : .off
        loginCheck.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menuBarCheck.state = menuBarIsOn() ? .on : .off
        appearanceControl.selectedSegment = (Appearance.mode == .glass) ? 0 : 1
    }

    @objc private func appearanceChanged() {
        Appearance.mode = (appearanceControl.selectedSegment == 0) ? .glass : .classic
    }

    /// Opens the two System Settings panes and shows the two manual steps.
    /// macOS gives no API to select a screen saver or set the idle delay,
    /// so this removes the hunting but the final picks are unavoidable.
    @objc private func setUpLockScreen() {
        let saver = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers/Driftwall.saver")
        let installed = FileManager.default.fileExists(atPath: saver.path)

        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")!)
        }

        let alert = NSAlert()
        alert.messageText = "Set Driftwall as your lock-screen saver"
        if installed {
            alert.informativeText = """
            Two quick picks (macOS has no API to do this automatically):

            1. Screen Saver → select Driftwall.
            2. Lock Screen → "Start Screen Saver when inactive" → 1 minute.

            Lock the Mac and wait that interval — Driftwall plays on the \
            lock screen and the login window.
            """
        } else {
            alert.informativeText = """
            The Driftwall screen saver isn't installed yet. Open the \
            Driftwall .dmg and double-click Driftwall.saver (or run \
            ./build-saver.sh --install), then come back and:

            1. Screen Saver → select Driftwall.
            2. Lock Screen → "Start Screen Saver when inactive" → 1 minute.
            """
        }
        alert.runModal()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            Appearance.register(window)
            if let vf = (window.screen ?? NSScreen.main)?.visibleFrame {
                // Never exceed the usable screen area, and keep the whole
                // window (titlebar to bottom) inside it — top-aligned so a
                // tall window doesn't run under the Dock.
                var f = window.frame
                f.size.height = min(f.size.height, vf.height)
                f.size.width = min(f.size.width, vf.width)
                f.origin.x = vf.midX - f.size.width / 2
                f.origin.y = vf.maxY - f.size.height
                window.setFrame(f, display: true)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video to use as your wallpaper"
        if panel.runModal() == .OK, let url = panel.url {
            controller.setVideo(url: url)
            refresh()
        }
    }

    @objc private func revealVideo() {
        if let url = controller.videoURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Wallpapers")
            NSWorkspace.shared.open(dir)
        }
    }

    @objc private func sourceChanged() {
        switch sourcePopup.indexOfSelectedItem {
        case 1:
            // Switching to playlist needs a folder; prompt if none yet.
            if controller.folderURL == nil { chooseFolder() }
            else { controller.sourceMode = .playlist }
        case 2:
            controller.sourceMode = .schedule
            // No slots yet — open the editor so it isn't a no-op.
            if controller.scheduleSlots.isEmpty { scheduleConfig.show() }
        default:
            controller.sourceMode = .single
        }
        refresh()
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of videos to crossfade through"
        if panel.runModal() == .OK, let url = panel.url {
            controller.setPlaylistFolder(url)
        }
        refresh()
    }

    @objc private func openStock() {
        stockBrowser.show()
    }

    func openStockBrowser() { openStock() }

    @objc private func openLibrary() {
        library.show()
    }

    @objc private func openDisplays() {
        displayConfig.show()
    }

    func openDisplaysWindow() { openDisplays() }

    @objc private func openSchedule() {
        scheduleConfig.show()
    }

    func openScheduleWindow() { openSchedule() }

    func openVideoLibrary() { openLibrary() }

    @objc private func saveKey() {
        let d = UserDefaults.standard
        d.set(apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              forKey: Self.pexelsKeyDefault)
        d.set(coverrKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              forKey: Self.coverrKeyDefault)
        d.set(pixabayKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
              forKey: Self.pixabayKeyDefault)
    }

    private func downloadAndUse(_ url: URL) {
        window?.makeKeyAndOrderFront(nil)
        beginProgress()
        VideoFetcher.shared.fetch(url.absoluteString, progress: { [weak self] frac in
            guard let self else { return }
            if let frac {
                self.progressBar.isIndeterminate = false
                self.progressBar.doubleValue = frac * 100
                self.progressLabel.stringValue = String(format: "Downloading… %.0f%%", frac * 100)
            } else {
                self.progressBar.isIndeterminate = true
                self.progressBar.startAnimation(nil)
                self.progressLabel.stringValue = "Downloading…"
            }
        }, completion: { [weak self] result in
            guard let self else { return }
            self.endProgress()
            switch result {
            case .success(let local):
                self.controller.setVideo(url: local)
                self.refresh()
            case .failure(let error):
                let a = NSAlert()
                a.messageText = "Couldn't download video"
                a.informativeText = error.localizedDescription
                a.runModal()
            }
        })
    }

    func promptAddFromURL() { addFromURL() }

    @objc private func addFromURL() {
        let alert = NSAlert()
        alert.messageText = "Add video from URL"
        alert.informativeText = """
        Paste a direct video link (.mp4 / .mov / .webm …) or a video page \
        (YouTube, Vimeo, etc. — uses yt-dlp).
        Only download videos you have the right to use.
        """
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        if let clip = NSPasteboard.general.string(forType: .string),
           clip.lowercased().hasPrefix("http") {
            field.stringValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        beginProgress()
        VideoFetcher.shared.fetch(input, progress: { [weak self] frac in
            guard let self else { return }
            if let frac {
                self.progressBar.isIndeterminate = false
                self.progressBar.doubleValue = frac * 100
                self.progressLabel.stringValue = String(format: "Downloading… %.0f%%", frac * 100)
            } else {
                self.progressBar.isIndeterminate = true
                self.progressBar.startAnimation(nil)
                self.progressLabel.stringValue = "Fetching via yt-dlp…"
            }
        }, completion: { [weak self] result in
            guard let self else { return }
            self.endProgress()
            switch result {
            case .success(let url):
                self.controller.setVideo(url: url)
                self.refresh()
            case .failure(let error):
                let a = NSAlert()
                a.messageText = "Couldn't add video"
                a.informativeText = error.localizedDescription
                a.runModal()
            }
        })
    }

    private func beginProgress() {
        guard let parent = window else { return }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 116),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Downloading"
        let v = sheet.contentView!

        progressLabel.stringValue = "Starting…"
        progressLabel.frame = NSRect(x: 20, y: 70, width: 340, height: 18)
        progressLabel.lineBreakMode = .byTruncatingTail

        progressBar.frame = NSRect(x: 20, y: 44, width: 340, height: 18)
        progressBar.style = .bar
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelDownload))
        cancel.frame = NSRect(x: 284, y: 10, width: 80, height: 28)

        v.addSubview(progressLabel)
        v.addSubview(progressBar)
        v.addSubview(cancel)

        parent.beginSheet(sheet, completionHandler: nil)
        progressSheet = sheet
    }

    private func endProgress() {
        if let s = progressSheet {
            window?.endSheet(s)
            progressSheet = nil
        }
    }

    @objc private func cancelDownload() {
        VideoFetcher.shared.cancel()
    }

    @objc private func toggleFill() { controller.fill = (fillCheck.state == .on) }
    @objc private func toggleMute() { controller.muted = (muteCheck.state == .on) }

    @objc private func speedChanged() {
        controller.speed = speedSlider.doubleValue
        speedLabel.stringValue = String(format: "%.2f×", controller.speed)
    }

    @objc private func toggleShuffle() { controller.shuffle = (shuffleCheck.state == .on) }

    @objc private func crossfadeChanged() {
        controller.crossfade = crossfadeSlider.doubleValue
        crossfadeLabel.stringValue = String(format: "%.1fs", controller.crossfade)
    }

    @objc private func clipMaxChanged() {
        controller.clipMax = clipMaxSlider.doubleValue.rounded()
        clipMaxLabel.stringValue = controller.clipMax < 1 ? "Full" : "\(Int(controller.clipMax))s"
    }

    @objc private func togglePause() { controller.togglePause(); refresh() }
    @objc private func toggleBattery() {
        controller.pauseOnBattery.toggle()
        if !controller.pauseOnBattery { BatteryWarning.showAfterDisable() }
        refresh()
    }
    @objc private func toggleLowPower() { controller.pauseOnLowPower = (lowPowerCheck.state == .on) }
    @objc private func toggleFullscreen() { controller.pauseOnFullscreen = (fullscreenCheck.state == .on) }
    @objc private func toggleReduceMotion() { controller.respectReduceMotion = (reduceMotionCheck.state == .on) }
    @objc private func toggleMenuBar() { setMenuBarVisible(menuBarCheck.state == .on) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login-item setting"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }
}
