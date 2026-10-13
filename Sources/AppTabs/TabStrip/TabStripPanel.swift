import AppKit
import AppTabsCore
import SwiftUI

/// The borderless, non-activating tab strip that hovers above a grouped window.
@MainActor
final class TabStripPanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    private let groupID: UUID
    private weak var coordinator: GroupCoordinator?
    private var hostingView: NSHostingView<TabStripView>?
    /// Avoids rebuilding the SwiftUI view when nothing visible changed.
    private var lastRenderedKey: RenderKey?

    private struct RenderKey: Equatable {
        var members: [CGWindowID]
        var memberColors: [String]
        var memberTitles: [String]
        var activeIndex: Int
    }

    init(coordinator: GroupCoordinator, groupID: UUID) {
        self.coordinator = coordinator
        self.groupID = groupID
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.isMovable = false
        super.init()
        panel.delegate = self

        rebuild()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: GroupCoordinator.groupsDidChangeNotification, object: coordinator)
    }

    func show(frame: CGRect) {
        // `frame` is the full-width candidate strip rect from FrameMath.
        // Shrink it to the actual tab content width, centered on the window,
        // so the strip grows outward from the middle as tabs are added.
        let tabCount = coordinator?.groups.first(where: { $0.id == groupID })?.members.count ?? 1
        let contentWidth = TabStripView.contentWidth(tabCount: tabCount)
        let width = min(contentWidth, frame.width)
        let adjusted = CGRect(
            x: frame.midX - width / 2,
            y: frame.origin.y,
            width: width,
            height: frame.height
        )
        // Skip the expensive setFrame + orderFront if the panel is already
        // exactly where it needs to be — NSWindow frame ops cost ~10ms each.
        if panel.frame == adjusted, panel.isVisible { return }
        if panel.frame != adjusted {
            panel.setFrame(adjusted, display: false)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        NotificationCenter.default.removeObserver(self)
        panel.close()
    }

    @objc func reload() {
        let key = coordinator?.groups.first(where: { $0.id == groupID }).map {
            RenderKey(members: $0.members.map(\.windowID),
                      memberColors: $0.members.map(\.colorID),
                      memberTitles: $0.members.map(\.displayTitle),
                      activeIndex: $0.activeIndex)
        }
        guard key != lastRenderedKey else { return }
        rebuild()
        // Width depends on tab count — reposition after content changes.
        if let group = coordinator?.groups.first(where: { $0.id == groupID }) {
            onContentChanged?(group)
        }
    }

    /// Set by the coordinator so content changes can trigger repositioning.
    var onContentChanged: ((TabGroup) -> Void)?

    private func rebuild() {
        guard let coordinator else { return }
        let group = coordinator.groups.first(where: { $0.id == groupID })
        lastRenderedKey = group.map {
            RenderKey(members: $0.members.map(\.windowID),
                      memberColors: $0.members.map(\.colorID),
                      memberTitles: $0.members.map(\.displayTitle),
                      activeIndex: $0.activeIndex)
        }
        let view = TabStripView(
            groupProvider: { [weak coordinator, groupID] in
                coordinator?.groups.first(where: { $0.id == groupID })
            },
            onSelect: { [weak coordinator, groupID] index in
                coordinator?.activateIndex(index, inGroup: groupID)
            },
            onDetach: { [weak coordinator] windowID in
                coordinator?.detach(windowID: windowID)
            },
            onReorder: { [weak coordinator, groupID] from, to in
                coordinator?.moveTab(in: groupID, from: from, to: to)
            },
            onContextAction: { [weak coordinator, groupID] action in
                Self.handle(action: action, coordinator: coordinator, groupID: groupID)
            },
            iconProvider: { pid in
                NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage()
            }
        )
        if let hosting = hostingView {
            hosting.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            panel.contentView = hosting
            hostingView = hosting
        }
    }

    private static func handle(action: TabStripContextAction, coordinator: GroupCoordinator?, groupID: UUID) {
        guard let coordinator else { return }
        switch action {
        case .ungroup:
            coordinator.ungroup(groupID)
        case .rename:
            let currentName = coordinator.groups.first(where: { $0.id == groupID })?.name ?? ""
            prompt(title: "Rename group", buttonLabel: "Rename", current: currentName,
                   coordinator: coordinator, groupID: groupID) { newName in
                coordinator.rename(groupID, to: newName)
            }
        case .renameTab(let windowID):
            let current = coordinator.groups.first(where: { $0.id == groupID })?
                .members.first(where: { $0.windowID == windowID })?.displayTitle ?? ""
            prompt(title: "Rename tab", buttonLabel: "Rename", current: current,
                   coordinator: coordinator, groupID: groupID) { newTitle in
                coordinator.renameTab(windowID, in: groupID, to: newTitle)
            }
        case .resetTabName(let windowID):
            coordinator.renameTab(windowID, in: groupID, to: "")
        case .setTabColor(let windowID, let token):
            coordinator.setColor(token, forMember: windowID, in: groupID)
        case .customTabColor(let windowID):
            NSApp.activate(ignoringOtherApps: true)
            ColorPanelCoordinator.shared.show(groupID: groupID, windowID: windowID, coordinator: coordinator)
        }
    }

    /// Modal text-entry dialog. Runs on the next run-loop turn so it isn't opened from
    /// inside a gesture callback, and hands focus back to the group afterwards.
    private static func prompt(title: String, buttonLabel: String, current: String,
                               coordinator: GroupCoordinator, groupID: UUID,
                               commit: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.stringValue = current
            alert.accessoryView = field
            alert.addButton(withTitle: buttonLabel)
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                commit(field.stringValue)
            }
            // Return focus to the grouped app — otherwise AppTabs stays frontmost
            // and the next click on another app pays a double activation cost.
            coordinator.focusGroup(groupID)
        }
    }
}

enum TabStripContextAction {
    case rename
    case ungroup
    case renameTab(CGWindowID)
    case resetTabName(CGWindowID)
    case setTabColor(CGWindowID, String)
    case customTabColor(CGWindowID)
}

/// Bridges NSColorPanel (target/action) to the coordinator.
@MainActor
final class ColorPanelCoordinator: NSObject {
    static let shared = ColorPanelCoordinator()

    private var groupID: UUID?
    private var windowID: CGWindowID?
    private weak var coordinator: GroupCoordinator?

    func show(groupID: UUID, windowID: CGWindowID, coordinator: GroupCoordinator) {
        self.groupID = groupID
        self.windowID = windowID
        self.coordinator = coordinator
        let panel = NSColorPanel.shared
        if let group = coordinator.groups.first(where: { $0.id == groupID }),
           let member = group.members.first(where: { $0.windowID == windowID }) {
            let rgb = GroupPalette.rgbComponents(GroupPalette.hex(for: member.colorID))
            panel.color = NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        }
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let groupID, let windowID, let coordinator else { return }
        let c = sender.color.usingColorSpace(.sRGB) ?? sender.color
        let hex = String(format: "#%02X%02X%02X",
                         Int(c.redComponent * 255),
                         Int(c.greenComponent * 255),
                         Int(c.blueComponent * 255))
        coordinator.setColor(hex, forMember: windowID, in: groupID)
    }
}
