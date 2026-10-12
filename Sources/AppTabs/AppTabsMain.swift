import AppKit
import AppTabsCore

@main
struct AppTabsMain {
    static func main() {
        let app = NSApplication.shared
        // Menu-bar app: no Dock icon, no activation by default.
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
