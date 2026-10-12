import AppKit
import AppTabsCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(coordinator: GroupCoordinator) {
        if window == nil {
            let view = SettingsView()
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "AppTabs Settings"
            window.contentView = hosting
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @AppStorage("parkInactiveWindows") private var parkInactive = false
    @State private var pickerShortcut: HotKeyCenter.Shortcut = HotKeyCenter.shared.currentShortcut

    var body: some View {
        Form {
            Section("Shortcuts") {
                HStack {
                    Text("Group windows:")
                    Spacer()
                    ShortcutRecorderView(shortcut: $pickerShortcut) { new in
                        HotKeyCenter.shared.register(shortcut: new) {
                            Task { @MainActor in
                                NotificationCenter.default.post(name: .appTabsShowPicker, object: nil)
                            }
                        }
                    }
                    .frame(width: 120, height: 24)
                }
            }
            Section("Behavior") {
                Toggle("Park inactive windows off-screen", isOn: $parkInactive)
                Text("When on, inactive tabs move off-screen so no other window can appear between group members.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Accessibility") {
                HStack {
                    Circle()
                        .fill(Permissions.isAccessibilityTrusted() ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(Permissions.isAccessibilityTrusted() ? "Accessibility permission granted" : "Accessibility permission required")
                    Spacer()
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

extension Notification.Name {
    static let appTabsShowPicker = Notification.Name("AppTabsShowPicker")
}
