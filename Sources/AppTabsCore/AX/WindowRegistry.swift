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
    /// Retries each app's window list a couple of times — a not-yet-effective AX
    /// trust grant (common right after toggling the checkbox or re-signing) returns
    /// `.apiDisabled`, and busy apps occasionally return `.cannotComplete`.
    public func enumerateWindows(
        applications: [(pid: pid_t, bundleID: String, appName: String)]
    ) -> [Entry] {
        var out: [Entry] = []
        for app in applications {
            let windows = axWindowsWithRetry(pid: app.pid)
            for element in windows {
                let window = AXWindow(element: element, pid: app.pid)
                guard window.isStandardWindow else { continue }
                out.append(Entry(window: window, bundleIdentifier: app.bundleID, appName: app.appName, pid: app.pid))
            }
        }
        return out
    }

    private func axWindowsWithRetry(pid: pid_t, attempts: Int = 3) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(pid)
        var lastError = AXError.success
        for attempt in 0..<attempts {
            var value: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
            switch err {
            case .success:
                return (value as? [AXUIElement]) ?? []
            case .apiDisabled:
                // Trust not effective yet for this process signature; brief wait then retry.
                lastError = err
                if attempt < attempts - 1 {
                    Thread.sleep(forTimeInterval: 0.3)
                }
            default:
                lastError = err
                if attempt < attempts - 1 {
                    Thread.sleep(forTimeInterval: 0.15)
                }
            }
        }
        if lastError != .success {
            NSLog("AppTabs: kAXWindowsAttribute failed for pid \(pid): \(lastError.rawValue)")
        }
        return []
    }

    /// Find an AX window by CGWindowID among the given apps.
    public func find(windowID: CGWindowID, in entries: [Entry]) -> AXWindow? {
        entries.first { $0.window.windowID == windowID }?.window
    }
}
