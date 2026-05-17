import Cocoa

/// One-time welcome shown on first launch. Driftwall has no Dock icon,
/// so the key message is *how to get back to it*.
final class OnboardingWindowController: NSWindowController {
    static let didOnboardKey = "DriftwallDidOnboard"

    var onFinish: () -> Void = {}

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Welcome to Driftwall"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        if let icon = NSApp.applicationIconImage {
            let iv = NSImageView(image: icon)
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 52).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 52).isActive = true
            header.addArrangedSubview(iv)
        }
        let title = NSTextField(labelWithString: "Driftwall")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        header.addArrangedSubview(title)
        stack.addArrangedSubview(header)

        let bullets = [
            "Driftwall lives in the menu bar — there's no Dock icon and no main window.",
            "To open settings later: launch Driftwall again (Spotlight or Finder), or click the menu-bar icon.",
            "Pick a video, paste a URL, or browse free stock clips — then it plays as your wallpaper.",
            "It pauses itself when covered, on battery, or in Low Power Mode to save energy.",
        ]
        for b in bullets {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 8
            let dot = NSTextField(labelWithString: "•")
            let text = NSTextField(wrappingLabelWithString: b)
            text.translatesAutoresizingMaskIntoConstraints = false
            text.widthAnchor.constraint(equalToConstant: 380).isActive = true
            row.addArrangedSubview(dot)
            row.addArrangedSubview(text)
            stack.addArrangedSubview(row)
        }

        let go = NSButton(title: "Open Settings", target: self, action: #selector(finish))
        go.keyEquivalent = "\r"
        stack.addArrangedSubview(go)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window { Appearance.register(window) }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func finish() {
        UserDefaults.standard.set(true, forKey: Self.didOnboardKey)
        window?.close()
        onFinish()
    }
}
