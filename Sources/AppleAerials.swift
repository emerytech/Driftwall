import Cocoa
import AVFoundation

private final class AAction: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func fire() { block() }
}

private final class AAFlipped: NSView {
    override var isFlipped: Bool { true }
}

/// Browse the Apple aerial videos macOS already downloaded to
/// com.apple.idleassetsd — zero key, zero network, instant 4K content.
final class AppleAerialsWindowController: NSWindowController {
    private let controller: WallpaperController
    var onChange: () -> Void = {}

    private let statusLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var actions: [AAction] = []
    private let preview = PreviewController()

    private let root = URL(fileURLWithPath:
        "/Library/Application Support/com.apple.idleassetsd")
    private let exts: Set<String> = ["mov", "mp4", "m4v"]

    init(controller: WallpaperController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Apple Aerials"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = AAFlipped()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        content.addSubview(statusLabel)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

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

    private func aerials() -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root,
                                    includingPropertiesForKeys: [.fileSizeKey]) else { return [] }
        var out: [URL] = []
        for case let u as URL in e where exts.contains(u.pathExtension.lowercased()) {
            out.append(u)
        }
        return out.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func reload() {
        actions.removeAll()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let vids = aerials()
        if vids.isEmpty {
            statusLabel.stringValue =
                "No Apple aerials downloaded yet. In System Settings → Wallpaper "
                + "or Screen Saver, pick an Apple “Aerial” once so macOS fetches "
                + "them, then reopen this window."
            return
        }
        statusLabel.stringValue = "\(vids.count) Apple aerial(s) — Preview, or Use to apply."
        for (i, url) in vids.enumerated() { addRow(url, index: i + 1) }
    }

    private func addRow(_ url: URL, index: Int) {
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
        let label = NSTextField(labelWithString: "Apple Aerial \(index)  ·  \(human)")
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let prev = NSButton(title: "Preview", target: nil, action: nil)
        prev.bezelStyle = .rounded
        let pa = AAction { [weak self] in self?.preview.show(url, title: "Apple Aerial \(index)") }
        actions.append(pa); prev.target = pa; prev.action = #selector(AAction.fire)

        let use = NSButton(title: "Use", target: nil, action: nil)
        use.bezelStyle = .rounded
        let ua = AAction { [weak self] in
            self?.controller.setVideo(url: url); self?.onChange()
        }
        actions.append(ua); use.target = ua; use.action = #selector(AAction.fire)

        [thumb, label, prev, use].forEach { row.addArrangedSubview($0) }
        stack.addArrangedSubview(row)

        DispatchQueue.global(qos: .userInitiated).async {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 320, height: 180)
            if let cg = try? gen.copyCGImage(
                at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil) {
                let img = NSImage(cgImage: cg, size: .zero)
                DispatchQueue.main.async { thumb.image = img }
            }
        }
    }
}
