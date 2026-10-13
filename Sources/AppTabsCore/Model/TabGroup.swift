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
    /// Per-tab color token: a GroupPalette named id ("blue") or custom hex ("#RRGGBB").
    public var colorID: String
    /// User-assigned tab name; overrides the window title when set.
    public var customTitle: String?

    public var id: CGWindowID { windowID }

    public init(windowID: CGWindowID, bundleIdentifier: String, windowTitle: String, pid: pid_t,
                colorID: String = "blue", customTitle: String? = nil) {
        self.windowID = windowID
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.pid = pid
        self.colorID = colorID
        self.customTitle = customTitle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windowID = try c.decode(CGWindowID.self, forKey: .windowID)
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        windowTitle = try c.decode(String.self, forKey: .windowTitle)
        pid = try c.decode(pid_t.self, forKey: .pid)
        colorID = try c.decodeIfPresent(String.self, forKey: .colorID) ?? "blue"
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
    }

    /// Name shown on the tab: custom name, else window title, else bundle identifier.
    public var displayTitle: String {
        if let t = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return windowTitle.isEmpty ? bundleIdentifier : windowTitle
    }

    /// Sets the custom name; blank input clears it so the tab shows the window title again.
    public mutating func setCustomTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        customTitle = trimmed.isEmpty ? nil : trimmed
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

    // Custom decoding so groups.json written before per-tab colors existed still loads.
    // A legacy group-level `colorID` is folded into each member that lacks one.
    private enum CodingKeys: String, CodingKey {
        case id, name, members, activeIndex, frame, parksInactiveWindows, colorID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        members = try c.decode([GroupMember].self, forKey: .members)
        activeIndex = try c.decode(Int.self, forKey: .activeIndex)
        frame = try c.decode(CGRect.self, forKey: .frame)
        parksInactiveWindows = try c.decodeIfPresent(Bool.self, forKey: .parksInactiveWindows) ?? false
        if let legacyColor = try c.decodeIfPresent(String.self, forKey: .colorID) {
            for i in members.indices where members[i].colorID == "blue" {
                members[i].colorID = legacyColor
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(members, forKey: .members)
        try c.encode(activeIndex, forKey: .activeIndex)
        try c.encode(frame, forKey: .frame)
        try c.encode(parksInactiveWindows, forKey: .parksInactiveWindows)
        // colorID intentionally not written at group level — colors live on members.
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

    /// Sets (or clears, for blank input) the custom name of the member with the given window ID.
    public mutating func setCustomTitle(_ title: String, forMember windowID: CGWindowID) {
        guard let idx = members.firstIndex(where: { $0.windowID == windowID }) else { return }
        members[idx].setCustomTitle(title)
    }
}
