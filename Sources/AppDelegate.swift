import Cocoa
import UniformTypeIdentifiers
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: WallpaperController!
    private var settings: SettingsWindowController!
    private var onboarding: OnboardingWindowController!
    private var statusItem: NSStatusItem?
    private weak var pauseMenuItem: NSMenuItem?
    private weak var batteryMenuItem: NSMenuItem?
    private weak var loginMenuItem: NSMenuItem?

    private static let showMenuBarKey = "DriftwallShowMenuBar"

    private var menuBarVisible: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showMenuBarKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showMenuBarKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            WallpaperController.Key.fill: true,
            WallpaperController.Key.speed: 1.0,
            WallpaperController.Key.muted: true,
            WallpaperController.Key.battery: true,
            WallpaperController.Key.crossfade: 1.5,
            WallpaperController.Key.lowPower: true,
            WallpaperController.Key.reduceMotion: true,
            WallpaperController.Key.fullscreen: true,
            Self.showMenuBarKey: true,
        ])

        controller = WallpaperController()
        if menuBarVisible { installStatusItem() }
        controller.start()

        settings = SettingsWindowController(controller: controller)
        settings.menuBarIsOn = { [weak self] in self?.menuBarVisible ?? true }
        settings.setMenuBarVisible = { [weak self] on in self?.setMenuBar(on) }

        let onboarded = UserDefaults.standard.bool(forKey: OnboardingWindowController.didOnboardKey)
        if !onboarded {
            let ob = OnboardingWindowController()
            onboarding = ob
            ob.onFinish = { [weak self] in self?.settings.show() }
            DispatchQueue.main.async { ob.show() }
        } else if !controller.hasVideo {
            // Already onboarded but nothing configured — jump to settings.
            DispatchQueue.main.async { [weak self] in self?.settings.show() }
        }
    }

    // Re-launching the app (double-click in Finder / Spotlight) reopens
    // the Settings window — the reliable way to manage a notch-hidden agent.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return true
    }

    func setMenuBar(_ on: Bool) {
        menuBarVisible = on
        if on, statusItem == nil {
            installStatusItem()
        } else if !on, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func menuBarImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBar", withExtension: "pdf"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        return NSImage(systemSymbolName: "photo.on.rectangle.angled",
                       accessibilityDescription: "Driftwall")
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuBarImage()

        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let choose = NSMenuItem(title: "Choose Video…",
                                action: #selector(chooseVideo), keyEquivalent: "o")
        choose.target = self
        menu.addItem(choose)

        let fromURL = NSMenuItem(title: "Add from URL…",
                                 action: #selector(menuAddFromURL), keyEquivalent: "u")
        fromURL.target = self
        menu.addItem(fromURL)

        let stock = NSMenuItem(title: "Browse Stock Videos…",
                               action: #selector(menuBrowseStock), keyEquivalent: "b")
        stock.target = self
        menu.addItem(stock)

        let lib = NSMenuItem(title: "Video Library…",
                             action: #selector(menuVideoLibrary), keyEquivalent: "l")
        lib.target = self
        menu.addItem(lib)

        let disp = NSMenuItem(title: "Displays…",
                              action: #selector(menuDisplays), keyEquivalent: "")
        disp.target = self
        menu.addItem(disp)

        let sched = NSMenuItem(title: "Schedule…",
                               action: #selector(menuSchedule), keyEquivalent: "")
        sched.target = self
        menu.addItem(sched)

        let pause = NSMenuItem(title: "Pause",
                               action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)
        pauseMenuItem = pause

        menu.addItem(.separator())

        let battery = NSMenuItem(title: "Pause on Battery",
                                 action: #selector(toggleBattery), keyEquivalent: "")
        battery.target = self
        menu.addItem(battery)
        batteryMenuItem = battery

        let login = NSMenuItem(title: "Launch at Login",
                               action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        loginMenuItem = login

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Driftwall",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    // Refresh checkmarks each time the menu opens (catches external changes
    // to the login-item state).
    func menuWillOpen(_ menu: NSMenu) {
        pauseMenuItem?.title = controller.isPaused ? "Resume" : "Pause"
        batteryMenuItem?.state = controller.pauseOnBattery ? .on : .off
        loginMenuItem?.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    @objc private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video to use as your wallpaper"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            controller.setVideo(url: url)
        }
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func menuAddFromURL() {
        settings.show()
        settings.promptAddFromURL()
    }

    @objc private func menuBrowseStock() {
        settings.show()
        settings.openStockBrowser()
    }

    @objc private func menuVideoLibrary() {
        settings.show()
        settings.openVideoLibrary()
    }

    @objc private func menuDisplays() {
        settings.show()
        settings.openDisplaysWindow()
    }

    @objc private func menuSchedule() {
        settings.show()
        settings.openScheduleWindow()
    }

    @objc private func togglePause() {
        controller.togglePause()
    }

    @objc private func toggleBattery() {
        controller.pauseOnBattery.toggle()
        if !controller.pauseOnBattery { BatteryWarning.showAfterDisable() }
    }

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
    }
}
