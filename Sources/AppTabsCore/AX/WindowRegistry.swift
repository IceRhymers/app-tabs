import ApplicationServices
import Foundation

/// Enumerates windows across running applications via the Accessibility API.
public final class WindowRegistry {
    public struct Entry {
        public let window: AXWindow
        public let bundleIdentifier: String
        public let appName: String
        public let pid: pid_t
    }

    public init() {}

    /// All standard windows across all apps that expose Accessibility.
    /// `providers`: closure returning [(pid, bundleID, appName)] so the app target can inject NSWorkspace data.
    public func enumerateWindows(
        applications: [(pid: pid_t, bundleID: String, appName: String)]
    ) -> [Entry] {
        var out: [Entry] = []
        for app in applications {
            let axApp = AXUIElementCreateApplication(app.pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for element in windows {
                let window = AXWindow(element: element, pid: app.pid)
                guard window.isStandardWindow else { continue }
                out.append(Entry(window: window, bundleIdentifier: app.bundleID, appName: app.appName, pid: app.pid))
            }
        }
        return out
    }

    /// Find an AX window by CGWindowID among the given apps.
    public func find(windowID: CGWindowID, in entries: [Entry]) -> AXWindow? {
        entries.first { $0.window.windowID == windowID }?.window
    }
}
