import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory == LSUIElement: no Dock icon, menu-bar only.
app.setActivationPolicy(.accessory)
app.run()
