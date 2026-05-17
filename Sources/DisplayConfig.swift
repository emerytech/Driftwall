import Cocoa
import UniformTypeIdentifiers

private final class Act: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func fire() { block() }
}

private final class FlippedDoc: NSView {
    override var isFlipped: Bool { true }
}

/// Per-display source overrides. Each connected display can use a
/// specific video, a playlist folder, or fall back to the global source.
final class DisplayConfigWindowController: NSWindowController {
    private let controller: WallpaperController
    var onChange: () -> Void = {}

    private let stack = NSStackView()
    private var actions: [Act] = []

    init(controller: WallpaperController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Displays"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let intro = NSTextField(wrappingLabelWithString:
            "Give a display its own video or playlist folder. "
            + "“Use default” reverts it to the global source.")
        intro.textColor = .secondaryLabelColor
        intro.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedDoc()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        content.addSubview(intro)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            intro.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            intro.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            intro.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 12),
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

    private func reload() {
        actions.removeAll()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        var seen = Set<String>()
        for key in controller.connectedDisplays() where seen.insert(key).inserted {
            let row = NSStackView()
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 4

            let name = NSTextField(labelWithString: key)
            name.font = .boldSystemFont(ofSize: 13)

            let cfg = controller.displayConfig(for: key)
            let currentText: String
            if let cfg {
                let kind = cfg.kind == "playlist" ? "Folder" : "Video"
                currentText = "\(kind): \((cfg.path as NSString).lastPathComponent)"
            } else {
                currentText = "Using global default"
            }
            let current = NSTextField(labelWithString: currentText)
            current.textColor = .secondaryLabelColor
            current.lineBreakMode = .byTruncatingMiddle
            current.translatesAutoresizingMaskIntoConstraints = false
            current.widthAnchor.constraint(equalToConstant: 540).isActive = true

            let buttons = NSStackView()
            buttons.orientation = .horizontal
            buttons.spacing = 8

            let vid = NSButton(title: "Use Video…", target: nil, action: nil)
            vid.bezelStyle = .rounded
            let vidA = Act { [weak self] in self?.pickVideo(for: key) }
            actions.append(vidA); vid.target = vidA; vid.action = #selector(Act.fire)

            let fold = NSButton(title: "Use Folder…", target: nil, action: nil)
            fold.bezelStyle = .rounded
            let foldA = Act { [weak self] in self?.pickFolder(for: key) }
            actions.append(foldA); fold.target = foldA; fold.action = #selector(Act.fire)

            let def = NSButton(title: "Use Default", target: nil, action: nil)
            def.bezelStyle = .rounded
            def.isEnabled = (cfg != nil)
            let defA = Act { [weak self] in
                self?.controller.clearDisplay(key); self?.onChange(); self?.reload()
            }
            actions.append(defA); def.target = defA; def.action = #selector(Act.fire)

            buttons.addArrangedSubview(vid)
            buttons.addArrangedSubview(fold)
            buttons.addArrangedSubview(def)

            row.addArrangedSubview(name)
            row.addArrangedSubview(current)
            row.addArrangedSubview(buttons)
            stack.addArrangedSubview(row)
        }
    }

    private func pickVideo(for key: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Video for “\(key)”"
        if panel.runModal() == .OK, let url = panel.url {
            controller.setDisplayVideo(key, url: url)
            onChange(); reload()
        }
    }

    private func pickFolder(for key: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Playlist folder for “\(key)”"
        if panel.runModal() == .OK, let url = panel.url {
            controller.setDisplayFolder(key, url: url)
            onChange(); reload()
        }
    }
}
