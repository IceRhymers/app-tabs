import CoreGraphics
import Foundation

/// A single window in a tab group.
public struct GroupMember: Codable, Equatable, Identifiable {
    /// Stable identifier while the window is alive (CGWindowID).
    public var windowID: CGWindowID
    public var bundleIdentifier: String
    /// Window title at time of grouping; used as fallback matcher on restore.
    public var windowTitle: String
    public var pid: pid_t

    public var id: CGWindowID { windowID }

    public init(windowID: CGWindowID, bundleIdentifier: String, windowTitle: String, pid: pid_t) {
        self.windowID = windowID
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.pid = pid
    }
}

/// A group of windows sharing one frame and one tab strip.
public struct TabGroup: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// Ordered list of tabs. The active member is `activeIndex`.
    public var members: [GroupMember]
    public var activeIndex: Int
    /// Last known shared frame (screen coordinates, top-left origin).
    public var frame: CGRect
    /// Whether inactive members are parked off-screen.
    public var parksInactiveWindows: Bool

    public init(id: UUID = UUID(), name: String, members: [GroupMember], activeIndex: Int = 0,
                frame: CGRect, parksInactiveWindows: Bool = false) {
        self.id = id
        self.name = name
        self.members = members
        self.activeIndex = activeIndex
        self.frame = frame
        self.parksInactiveWindows = parksInactiveWindows
    }

    public var activeMember: GroupMember? {
        guard members.indices.contains(activeIndex) else { return nil }
        return members[activeIndex]
    }

    public mutating func setActive(_ windowID: CGWindowID) {
        if let idx = members.firstIndex(where: { $0.windowID == windowID }) {
            activeIndex = idx
        }
    }

    @discardableResult
    public mutating func remove(_ windowID: CGWindowID) -> Bool {
        guard let idx = members.firstIndex(where: { $0.windowID == windowID }) else { return false }
        members.remove(at: idx)
        if activeIndex >= members.count {
            activeIndex = max(0, members.count - 1)
        }
        return true
    }

    public mutating func move(from source: Int, to destination: Int) {
        guard members.indices.contains(source), destination >= 0, destination <= members.count else { return }
        let item = members.remove(at: source)
        members.insert(item, at: destination == members.count + 1 ? members.count : destination)
        if let active = members.firstIndex(where: { $0.windowID == item.windowID }) {
            _ = active
        }
    }
}
