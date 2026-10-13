import AppKit
import AppTabsCore
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: GroupCoordinator
    private let onShowPicker: () -> Void
    private let onShowSettings: () -> Void
    private var observer: NSObjectProtocol?

    init(coordinator: GroupCoordinator, onShowPicker: @escaping () -> Void, onShowSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onShowPicker = onShowPicker
        self.onShowSettings = onShowSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "AppTabs")
            image?.isTemplate = true
            button.image = image
        }
        rebuildMenu()
        observer = NotificationCenter.default.addObserver(forName: GroupCoordinator.groupsDidChangeNotification, object: coordinator, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuildMenu() }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let pickerItem = NSMenuItem(title: "Group Windows…", action: #selector(showPicker), keyEquivalent: "")
        pickerItem.target = self
        menu.addItem(pickerItem)
        menu.addItem(.separator())

        if coordinator.groups.isEmpty {
            menu.addItem(NSMenuItem(title: "No groups", action: nil, keyEquivalent: ""))
        } else {
            for group in coordinator.groups {
                let item = NSMenuItem(title: "\(group.name) (\(group.members.count) tabs)", action: #selector(focusGroup(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = group.id
                item.image = colorDot(hex: GroupPalette.hex(for: group.activeMember?.colorID ?? "blue"))
                menu.addItem(item)
                let sub = NSMenu()
                for member in group.members {
                    let mi = NSMenuItem(title: member.displayTitle, action: #selector(activateTab(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.representedObject = ["group": group.id.uuidString, "window": NSNumber(value: member.windowID)]
                    sub.addItem(mi)
                }
                menu.setSubmenu(sub, for: item)
            }
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quit = NSMenuItem(title: "Quit AppTabs", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func showPicker() { onShowPicker() }
    @objc private func showSettings() { onShowSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func colorDot(hex: String) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            let rgb = GroupPalette.rgbComponents(hex)
            NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        return image
    }

    @objc private func focusGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        coordinator.focusGroup(id)
    }

    @objc private func activateTab(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let uuidStr = info["group"] as? String,
              let uuid = UUID(uuidString: uuidStr),
              let windowNum = info["window"] as? NSNumber else { return }
        coordinator.activate(windowID: CGWindowID(windowNum.uint32Value), inGroup: uuid)
    }
}
