import ApplicationServices
import CoreGraphics
import Foundation

/// A lightweight description of an on-screen window from the window server.
public struct WindowInfo: Hashable {
    public let windowID: CGWindowID
    public let pid: pid_t
    public let ownerName: String
    public let title: String
    public let frame: CGRect
    public let isOnScreen: Bool

    public init(windowID: CGWindowID, pid: pid_t, ownerName: String, title: String, frame: CGRect, isOnScreen: Bool) {
        self.windowID = windowID
        self.pid = pid
        self.ownerName = ownerName
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
    }
}

public enum WindowList {
    /// All on-screen, standard-layer windows in front-to-back order, excluding our own app.
    public static func onScreenWindows(excludingPID excluded: pid_t? = nil) -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { dict -> WindowInfo? in
            guard
                let id = dict[kCGWindowNumber as String] as? CGWindowID,
                let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                pid != excluded
            else { return nil }
            let layer = dict[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { return nil }
            let alpha = dict[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { return nil }
            let boundsDict = dict[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero
            guard frame.width > 60, frame.height > 60 else { return nil }
            let owner = dict[kCGWindowOwnerName as String] as? String ?? ""
            let title = dict[kCGWindowName as String] as? String ?? ""
            return WindowInfo(windowID: id, pid: pid, ownerName: owner, title: title, frame: frame, isOnScreen: true)
        }
    }

    /// The topmost standard window whose frame contains the given screen point.
    public static func windowUnderPoint(_ point: CGPoint, excludingPIDs: [pid_t] = []) -> WindowInfo? {
        onScreenWindows().first { !excludingPIDs.contains($0.pid) && $0.frame.contains(point) }
    }
}
