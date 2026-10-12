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
        super.init()
        panel.delegate = self

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
            iconProvider: { [weak coordinator] pid in
                NSRunningApplication(processIdentifier: pid)?.icon ?? NSImage()
            }
        )
        let hosting = NSHostingView(rootView: view)
        panel.contentView = hosting
        hostingView = hosting

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: GroupCoordinator.groupsDidChangeNotification, object: coordinator)
    }

    func show(frame: CGRect) {
        panel.setFrame(frame, display: false)
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
        // Trigger SwiftUI refresh by re-setting the rootView's provider path.
        hostingView?.rootView = TabStripView(
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
    }

    private static func handle(action: TabStripContextAction, coordinator: GroupCoordinator?, groupID: UUID) {
        guard let coordinator else { return }
        switch action {
        case .ungroup:
            coordinator.ungroup(groupID)
        case .rename:
            let alert = NSAlert()
            alert.messageText = "Rename group"
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.stringValue = coordinator.groups.first(where: { $0.id == groupID })?.name ?? ""
            alert.accessoryView = field
            alert.addButton(withTitle: "Rename")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                coordinator.rename(groupID, to: field.stringValue)
            }
        }
    }
}

enum TabStripContextAction {
    case rename
    case ungroup
}
