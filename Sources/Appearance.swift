import Cocoa

enum AppearanceMode: String {
    case glass, classic
}

/// Centralized window chrome. Glass = translucent vibrancy material with
/// a transparent titlebar (the wallpaper blurs through). Classic = the
/// original solid window. Tracked windows update live on toggle.
enum Appearance {
    static let key = "DriftwallAppearance"
    private static let bgID = NSUserInterfaceItemIdentifier("DriftwallGlassBG")
    private static let tracked = NSHashTable<NSWindow>.weakObjects()

    static var mode: AppearanceMode {
        get { AppearanceMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "glass") ?? .glass }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            tracked.allObjects.forEach { apply(to: $0) }
        }
    }

    /// Register once per window — also applies the current mode.
    static func register(_ window: NSWindow) {
        if !tracked.contains(window) { tracked.add(window) }
        apply(to: window)
    }

    static func apply(to window: NSWindow) {
        guard let content = window.contentView else { return }
        let existing = content.subviews.first { $0.identifier == bgID } as? NSVisualEffectView

        switch mode {
        case .glass:
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            let effect: NSVisualEffectView
            if let existing {
                effect = existing
            } else {
                effect = NSVisualEffectView(frame: content.bounds)
                effect.identifier = bgID
                effect.autoresizingMask = [.width, .height]
                effect.blendingMode = .behindWindow
                effect.state = .active
                content.addSubview(effect, positioned: .below, relativeTo: nil)
            }
            effect.material = .underWindowBackground

        case .classic:
            existing?.removeFromSuperview()
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
        }
    }
}
