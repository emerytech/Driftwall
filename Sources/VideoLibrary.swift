import Cocoa
import AVFoundation

private final class FlippedDoc: NSView {
    override var isFlipped: Bool { true }
}

private final class Action: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func fire() { block() }
}

/// Browse, preview, set, reveal, or trash videos in the library folder
/// (~/Wallpapers — where URL/stock downloads land).
final class LibraryWindowController: NSWindowController {
    private let controller: WallpaperController
    var onChange: () -> Void = {}

    private let statusLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var actions: [Action] = []
    private let preview = PreviewController()

    private let exts: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi"]
    private var libraryDir: URL { VideoFetcher.shared.destinationDir }

    init(controller: WallpaperController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Video Library"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let revealFolder = NSButton(title: "Open Folder in Finder",
                                    target: self, action: #selector(openFolder))
        revealFolder.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedDoc()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        content.addSubview(statusLabel)
        content.addSubview(revealFolder)
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            revealFolder.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            revealFolder.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),

            stack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: doc.bottomAnchor, constant: -4),
        ])
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window { Appearance.register(window) }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        reload()
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(libraryDir)
    }

    private func reload() {
        actions.removeAll()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let items = (try? FileManager.default.contentsOfDirectory(
            at: libraryDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]))
            ?? []
        let videos = items
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }

        if videos.isEmpty {
            statusLabel.stringValue = "No videos in \(libraryDir.path) yet. "
                + "Use Add from URL / Stock / Choose Video to fill it."
            return
        }
        statusLabel.stringValue = "\(videos.count) video(s) in \(libraryDir.lastPathComponent)"
        videos.forEach { addRow($0) }
    }

    private func addRow(_ url: URL) {
        let isCurrent = controller.videoURL?.standardizedFileURL == url.standardizedFileURL
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let thumb = NSImageView()
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.backgroundColor = NSColor.black.cgColor
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.widthAnchor.constraint(equalToConstant: 160).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 90).isActive = true

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let human = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        let name = (isCurrent ? "● " : "") + url.lastPathComponent
        let label = NSTextField(labelWithString: "\(name)\n\(human)")
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.textColor = isCurrent ? .controlAccentColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 260).isActive = true

        let useBtn = NSButton(title: isCurrent ? "Current" : "Use",
                              target: nil, action: nil)
        useBtn.bezelStyle = .rounded
        useBtn.isEnabled = !isCurrent
        let useA = Action { [weak self] in
            self?.controller.setVideo(url: url)
            self?.onChange()
            self?.reload()
        }
        actions.append(useA); useBtn.target = useA; useBtn.action = #selector(Action.fire)

        let prevBtn = NSButton(title: "Preview", target: nil, action: nil)
        prevBtn.bezelStyle = .rounded
        let prevA = Action { [weak self] in
            self?.preview.show(url, title: url.lastPathComponent)
        }
        actions.append(prevA); prevBtn.target = prevA; prevBtn.action = #selector(Action.fire)

        let revealBtn = NSButton(title: "Reveal", target: nil, action: nil)
        revealBtn.bezelStyle = .rounded
        let revealA = Action {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        actions.append(revealA); revealBtn.target = revealA; revealBtn.action = #selector(Action.fire)

        let delBtn = NSButton(title: "Delete", target: nil, action: nil)
        delBtn.bezelStyle = .rounded
        let delA = Action { [weak self] in self?.confirmDelete(url, isCurrent: isCurrent) }
        actions.append(delA); delBtn.target = delA; delBtn.action = #selector(Action.fire)

        [thumb, label, prevBtn, useBtn, revealBtn, delBtn].forEach { row.addArrangedSubview($0) }
        stack.addArrangedSubview(row)

        // Thumbnail off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 320, height: 180)
            let t = CMTime(seconds: 1, preferredTimescale: 600)
            if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
                let img = NSImage(cgImage: cg, size: .zero)
                DispatchQueue.main.async { thumb.image = img }
            }
        }
    }

    private func confirmDelete(_ url: URL, isCurrent: Bool) {
        let alert = NSAlert()
        alert.messageText = "Move “\(url.lastPathComponent)” to Trash?"
        alert.informativeText = isCurrent
            ? "This is the current wallpaper. It keeps playing until you "
              + "pick another or restart Driftwall."
            : "The file is moved to the Trash (recoverable)."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        reload()
    }
}
