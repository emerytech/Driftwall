import Cocoa

/// Minimal update check: ask the GitHub Releases API for the latest tag,
/// compare it to the running version, and if newer offer to open the
/// release page. No dependencies, no auto-install (Homebrew users get a
/// one-line `brew upgrade`); deliberately lightweight.
enum Updater {
    private static let repo = "emerytech/Driftwall"

    static func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// `explicit` = the user clicked "Check for Updates…" (show the
    /// up-to-date / error result). A silent launch check passes false.
    static func check(explicit: Bool) {
        let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12

        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                guard let data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    if explicit {
                        notify("Couldn’t check for updates",
                               err?.localizedDescription ?? "No response from GitHub.")
                    }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let current = currentVersion()
                if isNewer(latest, than: current) {
                    let page = (json["html_url"] as? String).flatMap(URL.init(string:))
                    offer(current: current, latest: latest, page: page)
                } else if explicit {
                    notify("You’re up to date",
                           "Driftwall \(current) is the latest version.")
                }
            }
        }.resume()
    }

    /// Quiet check at launch, at most once per 24h (never nags; only
    /// surfaces an alert when an update is actually available).
    static func checkOnLaunch() {
        let key = "DriftwallLastUpdateCheck"
        let now = Date().timeIntervalSince1970
        if now - UserDefaults.standard.double(forKey: key) < 86_400 { return }
        UserDefaults.standard.set(now, forKey: key)
        check(explicit: false)
    }

    /// Dot-separated numeric compare so 0.10 > 0.9 and 1.0 > 0.9.9.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0 ..< max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func offer(current: String, latest: String, page: URL?) {
        let a = NSAlert()
        a.messageText = "Update available"
        a.informativeText = """
        Driftwall \(latest) is available — you have \(current).

        Homebrew: run  brew upgrade --cask driftwall
        Otherwise, download the new version below.
        """
        a.addButton(withTitle: "Download…")
        a.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                page ?? URL(string: "https://github.com/\(repo)/releases/latest")!)
        }
    }

    private static func notify(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
