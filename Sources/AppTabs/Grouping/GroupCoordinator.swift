import AppKit
import AppTabsCore
import ApplicationServices

/// Owns all window groups: creation, tab switching, frame sync, persistence, strip management.
@MainActor
public final class GroupCoordinator: ObservableObject {
    public static let groupsDidChangeNotification = Notification.Name("AppTabsGroupsDidChange")

    @Published public private(set) var groups: [TabGroup] = []

    public var onGroupsChanged: (() -> Void)?

    private let registry = WindowRegistry()
    private let store = GroupStore()
    private var observerHub: AXObserverHub?
    private var stripControllers: [UUID: TabStripPanelController] = [:]
    /// True while we are programmatically moving windows, to ignore our own AX noise.
    private var suppressAXReactions = false
    /// Debounce for applying group frames to inactive members.
    private var applyFrameWorkItem: DispatchWorkItem?
    /// Avoid double-restoring.
    private var didRestore = false

    public init() {
        observerHub = AXObserverHub { [weak self] event in
            Task { @MainActor in self?.handleAXEvent(event) }
        }
        NotificationCenter.default.addObserver(self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(activeAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self,
            selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: - Window enumeration

    public struct PickerItem: Identifiable, Hashable {
        public let id: CGWindowID
        public let windowID: CGWindowID
        public let appName: String
        public let bundleIdentifier: String
        public let title: String
        public let icon: NSImage
        public let pid: pid_t
        public var isGrouped: Bool
    }

    public func enumerateOpenWindows() -> [PickerItem] {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }.map { (pid: $0.processIdentifier, bundleID: $0.bundleIdentifier ?? "", appName: $0.localizedName ?? "") }

        for app in apps { observerHub?.watch(pid: app.pid) }

        let entries = registry.enumerateWindows(applications: apps)
        let groupedIDs = Set(groups.flatMap { $0.members.map(\.windowID) })
        return entries.compactMap { entry in
            let id = entry.window.windowID
            guard id != 0 else { return nil }
            guard !entry.window.isMinimized, !entry.window.isFullScreen else { return nil }
            let icon = NSRunningApplication(processIdentifier: entry.pid)?.icon ?? NSImage()
            return PickerItem(id: id, windowID: id, appName: entry.appName,
                              bundleIdentifier: entry.bundleIdentifier,
                              title: entry.window.title ?? entry.appName,
                              icon: icon, pid: entry.pid, isGrouped: groupedIDs.contains(id))
        }
    }

    private func axWindow(for windowID: CGWindowID, pid: pid_t) -> AXWindow? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for el in windows {
            let w = AXWindow(element: el, pid: pid)
            if w.windowID == windowID { return w }
        }
        return nil
    }

    // MARK: - Grouping

    @discardableResult
    public func createGroup(name: String? = nil, windowIDs: [(id: CGWindowID, pid: pid_t)]) -> TabGroup? {
        var members: [GroupMember] = []
        var frame = CGRect.zero
        for item in windowIDs {
            guard let ax = axWindow(for: item.id, pid: item.pid), ax.isStandardWindow else { continue }
            let bundleID = NSRunningApplication(processIdentifier: item.pid)?.bundleIdentifier ?? ""
            if frame == .zero { frame = ax.frame }
            members.append(GroupMember(windowID: item.id, bundleIdentifier: bundleID,
                                       windowTitle: ax.title ?? "", pid: item.pid))
        }
        guard members.count >= 2 else { return nil }
        let defaultName = "Group \(groups.count + 1)"
        var group = TabGroup(name: name ?? defaultName, members: members, activeIndex: 0, frame: frame)
        groups.append(group)
        alignAndShow(&group)
        notify()
        return group
    }

    public func add(windowID: CGWindowID, pid: pid_t, to groupID: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }),
              let ax = axWindow(for: windowID, pid: pid),
              ax.isStandardWindow,
              !groups[gi].members.contains(where: { $0.windowID == windowID }) else { return }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        groups[gi].members.append(GroupMember(windowID: windowID, bundleIdentifier: bundleID,
                                              windowTitle: ax.title ?? "", pid: pid))
        alignAndShow(&groups[gi])
        notify()
    }

    public func detach(windowID: CGWindowID) {
        guard let gi = groups.firstIndex(where: { $0.members.contains(where: { $0.windowID == windowID }) }) else { return }
        groups[gi].remove(windowID)
        if groups[gi].members.count < 2 {
            dissolve(at: gi)
        } else {
            alignAndShow(&groups[gi])
        }
        notify()
    }

    public func ungroup(_ groupID: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        dissolve(at: gi)
        notify()
    }

    private func dissolve(at index: Int) {
        let group = groups.remove(at: index)
        stripControllers[group.id]?.close()
        stripControllers[group.id] = nil
    }

    public func rename(_ groupID: UUID, to name: String) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gi].name = name
        stripControllers[groupID]?.reload()
        notify()
    }

    // MARK: - Tab switching

    public func activate(windowID: CGWindowID, inGroup groupID: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gi].setActive(windowID)
        alignAndShow(&groups[gi])
        notify()
    }

    public func activateIndex(_ index: Int, inGroup groupID: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }),
              groups[gi].members.indices.contains(index) else { return }
        groups[gi].activeIndex = index
        alignAndShow(&groups[gi])
        notify()
    }

    public func focusGroup(_ groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }),
              let active = group.activeMember else { return }
        NSRunningApplication(processIdentifier: active.pid)?.activate(options: [.activateIgnoringOtherApps])
        if let ax = axWindow(for: active.windowID, pid: active.pid) {
            ax.raise()
        }
        orderStrips()
    }

    // MARK: - Reorder

    public func moveTab(in groupID: UUID, from source: Int, to destination: Int) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let activeID = groups[gi].activeMember?.windowID
        groups[gi].move(from: source, to: destination)
        if let activeID { groups[gi].setActive(activeID) }
        stripControllers[groupID]?.reload()
        notify()
    }

    // MARK: - Frame sync (the heart)

    /// Bring all members to the group's frame, raise the active one, position the strip.
    private func alignAndShow(_ group: inout TabGroup, debounceApply: Bool = false) {
        guard let active = group.activeMember,
              let activeAX = axWindow(for: active.windowID, pid: active.pid) else {
            stripControllers[group.id]?.hide()
            return
        }

        // Adopt the active window's current frame as the group frame.
        group.frame = activeAX.frame

        // Snapshot for the closure (avoid capturing the inout parameter).
        let snapshot = group

        suppressAXReactions = true
        defer { suppressAXReactions = false }

        let apply = { [weak self] in
            guard let self else { return }
            self.suppressAXReactions = true
            defer { self.suppressAXReactions = false }
            for member in snapshot.members where member.windowID != active.windowID {
                guard var ax = self.axWindow(for: member.windowID, pid: member.pid) else { continue }
                if snapshot.parksInactiveWindows {
                    if ax.frame != snapshot.frame { ax.frame = snapshot.frame }
                    ax.set(position: FrameMath.parkingSpot.origin)
                } else {
                    if ax.frame != snapshot.frame { ax.frame = snapshot.frame }
                }
            }
        }

        if debounceApply {
            applyFrameWorkItem?.cancel()
            let item = DispatchWorkItem(block: apply)
            applyFrameWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        } else {
            apply()
        }

        // Raise active window & activate its app.
        NSRunningApplication(processIdentifier: active.pid)?.activate(options: [.activateIgnoringOtherApps])
        activeAX.raise()

        showStrip(for: group)
        orderStrips()
    }

    private func showStrip(for group: TabGroup) {
        guard let active = group.activeMember,
              let activeAX = axWindow(for: active.windowID, pid: active.pid) else { return }
        let axFrame = activeAX.frame
        let center = CGPoint(x: axFrame.midX, y: axFrame.midY)
        let screen = NSScreen.screens.first { NSPointInRect(convertAXPoint(center), $0.frame) }
            ?? NSScreen.main
        guard let screen else { return }

        let stripFrame = FrameMath.stripFrame(forWindowFrame: axFrame,
                                              screenVisibleFrame: screen.visibleFrame,
                                              screenFrame: screen.frame)
        let controller = stripControllers[group.id] ?? {
            let c = TabStripPanelController(coordinator: self, groupID: group.id)
            stripControllers[group.id] = c
            return c
        }()
        controller.show(frame: stripFrame)
    }

    /// Keep each strip just above its group's active window in z-order.
    private func orderStrips() {
        for group in groups {
            guard let active = group.activeMember,
                  let activeAX = axWindow(for: active.windowID, pid: active.pid),
                  let strip = stripControllers[group.id]?.panel else { continue }
            let wid = Int(activeAX.windowID)
            strip.order(.above, relativeTo: wid)
        }
    }

    // MARK: - AX events

    private func handleAXEvent(_ event: AXObserverHub.Event) {
        guard !suppressAXReactions else { return }
        switch event {
        case .windowMoved(let pid), .windowResized(let pid):
            // A grouped window moved: re-sync group to its frame.
            guard let gi = groups.firstIndex(where: { g in
                g.members.contains { $0.pid == pid && $0.windowID == g.activeMember?.windowID }
            }) else { return }
            var group = groups[gi]
            alignAndShow(&group, debounceApply: true)
            groups[gi] = group

        case .windowDestroyed(let pid):
            handleWindowDestroyed(pid: pid)

        case .windowCreated(let pid):
            // Nothing to do for now (rules engine comes later).
            _ = pid

        case .focusedWindowChanged(let pid):
            // If user focused a non-active member of a group, make it active.
            guard let gi = groups.firstIndex(where: { g in g.members.contains { $0.pid == pid } }) else { return }
            let group = groups[gi]
            // Find which member window of this pid is now focused.
            let app = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
                  let focused = value,
                  CFGetTypeID(focused) == AXUIElementGetTypeID() else { return }
            let focusedWindow = AXWindow(element: unsafeBitCast(focused, to: AXUIElement.self), pid: pid)
            let focusedID = focusedWindow.windowID
            if focusedID != 0, let member = group.members.first(where: { $0.windowID == focusedID }),
               member.windowID != group.activeMember?.windowID {
                groups[gi].setActive(focusedID)
                var g = groups[gi]
                alignAndShow(&g)
                groups[gi] = g
                notify()
            }
            orderStrips()

        case .appTerminated(let pid):
            handleWindowDestroyed(pid: pid)
        }
    }

    private func handleWindowDestroyed(pid: pid_t) {
        var changed = false
        for gi in groups.indices.reversed() {
            let group = groups[gi]
            for member in group.members where member.pid == pid {
                // Check if the window still exists.
                if axWindow(for: member.windowID, pid: member.pid) == nil {
                    groups[gi].remove(member.windowID)
                    changed = true
                }
            }
            if groups.indices.contains(gi), groups[gi].members.count < 2 {
                dissolve(at: gi)
                changed = true
            } else if groups.indices.contains(gi) {
                var g = groups[gi]
                alignAndShow(&g)
            }
        }
        if changed { notify() }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        observerHub?.unwatch(pid: app.processIdentifier)
        handleWindowDestroyed(pid: app.processIdentifier)
    }

    @objc private func activeAppChanged(_ note: Notification) {
        orderStrips()
    }

    @objc private func screensChanged(_ note: Notification) {
        FrameMathConfig.install()
        for i in groups.indices {
            var g = groups[i]
            alignAndShow(&g)
            groups[i] = g
        }
    }

    // MARK: - Persistence

    public func saveGroups() {
        do {
            try store.save(groups: groups)
        } catch {
            NSLog("AppTabs: failed to save groups: \(error)")
        }
    }

    public func restoreGroups() {
        guard !didRestore else { return }
        didRestore = true
        guard let saved = try? store.load(), !saved.isEmpty else { return }

        let openItems = enumerateOpenWindows()
        let openMembers = openItems.map {
            GroupMember(windowID: $0.windowID, bundleIdentifier: $0.bundleIdentifier, windowTitle: $0.title, pid: $0.pid)
        }
        for var group in saved {
            let restored = GroupMatcher.restore(members: group.members, open: openMembers)
            guard restored.count >= 2 else { continue }
            group.members = restored
            if group.activeIndex >= group.members.count { group.activeIndex = 0 }
            groups.append(group)
            alignAndShow(&group)
        }
        notify()
    }

    // MARK: - Change notification

    private func notify() {
        NotificationCenter.default.post(name: Self.groupsDidChangeNotification, object: self)
        onGroupsChanged?()
    }

    // MARK: - Helpers

    public func screenPointToAppKit(_ p: CGPoint) -> CGPoint {
        convertAXPoint(p)
    }

    /// AX coordinates (top-left origin) → AppKit (bottom-left origin).
    private func convertAXPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: NSScreenPrimaryHeightProvider.height - p.y)
    }

    /// Find group whose *strip* contains the given AppKit point.
    public func stripAtAppKitPoint(_ p: CGPoint) -> UUID? {
        for (id, controller) in stripControllers {
            if controller.panel.frame.contains(p) { return id }
        }
        return nil
    }

    /// Find the group whose active window contains the given AppKit point (excluding own windows).
    public func groupAtAppKitPoint(_ p: CGPoint) -> UUID? {
        for group in groups {
            guard let active = group.activeMember,
                  let ax = axWindow(for: active.windowID, pid: active.pid) else { continue }
            let f = FrameMath.axToAppKit(ax.frame, screenFrame: .zero)
            if f.contains(p) { return group.id }
        }
        return nil
    }

    /// Resolve an AX window + pid from a CGWindowID for drag-to-group.
    public func memberInfo(for windowID: CGWindowID, pid: pid_t) -> (CGWindowID, pid_t)? {
        (windowID, pid)
    }
}
