import AppKit
import AppTabsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var coordinator: GroupCoordinator!
    private var pickerController: WindowPickerPanel?
    private var dragMonitor: DragToGroupMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Let the core know the primary screen height for coordinate conversions.
        FrameMathConfig.install()

        coordinator = GroupCoordinator()
        menuBar = MenuBarController(coordinator: coordinator, onShowPicker: { [weak self] in
            self?.showPicker()
        }, onShowSettings: { [weak self] in
            self?.showSettings()
        })

        // Accessibility permission
        if !Permissions.isAccessibilityTrusted() {
            Permissions.requestAccessibility(prompt: true)
        }
        Task {
            _ = await Permissions.waitForTrust(timeout: 600)
            coordinator.restoreGroups()
        }

        // Global hotkey
        HotKeyCenter.shared.register(shortcut: HotKeyCenter.shared.currentShortcut) { [weak self] in
            Task { @MainActor in self?.showPicker() }
        }

        // Drag-to-group
        dragMonitor = DragToGroupMonitor(coordinator: coordinator)
        dragMonitor?.start()

        // Persist groups when windows close / apps quit, and on terminate.
        NotificationCenter.default.addObserver(self, selector: #selector(save), name: NSApplication.willTerminateNotification, object: nil)
        coordinator.onGroupsChanged = { [weak self] in self?.save() }
    }

    @objc private func save() {
        coordinator.saveGroups()
    }

    private func showPicker() {
        if pickerController == nil {
            pickerController = WindowPickerPanel(coordinator: coordinator)
        }
        pickerController?.refresh()
        pickerController?.show()
    }

    private func showSettings() {
        SettingsWindowController.shared.show(coordinator: coordinator)
    }
}

enum FrameMathConfig {
    @MainActor
    static func install() {
        NSScreenPrimaryHeightProvider.height = NSScreen.screens.first(where: {
            $0.frame.origin == .zero
        })?.frame.height ?? NSScreen.main?.frame.height ?? 1080
    }
}
