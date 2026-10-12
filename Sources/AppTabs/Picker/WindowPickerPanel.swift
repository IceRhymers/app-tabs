import AppKit
import AppTabsCore
import SwiftUI

/// Searchable window picker: pick multiple windows, group them, or add them to an existing group.
@MainActor
final class WindowPickerPanel: NSObject {
    private var panel: NSPanel?
    private weak var coordinator: GroupCoordinator?

    init(coordinator: GroupCoordinator) {
        self.coordinator = coordinator
    }

    func refresh() {
        // Rebuild view each show so the list is fresh.
        panel?.close()
        panel = nil
    }

    func show() {
        guard let coordinator else { return }
        let model = PickerModel(coordinator: coordinator)
        let view = WindowPickerView(model: model) { [weak self] in
            self?.panel?.close()
        }
        let hosting = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Group Windows"
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }
}

@MainActor
final class PickerModel: ObservableObject {
    @Published var search: String = ""
    @Published private(set) var items: [GroupCoordinator.PickerItem] = []
    @Published var selection = Set<CGWindowID>()
    @Published var groupName: String = ""
    @Published var targetExistingGroup: UUID?

    let coordinator: GroupCoordinator

    init(coordinator: GroupCoordinator) {
        self.coordinator = coordinator
        reload()
    }

    func reload() {
        items = coordinator.enumerateOpenWindows()
    }

    var filtered: [GroupCoordinator.PickerItem] {
        guard !search.isEmpty else { return items }
        let q = search.lowercased()
        return items.filter {
            $0.title.lowercased().contains(q) ||
            $0.appName.lowercased().contains(q) ||
            $0.bundleIdentifier.lowercased().contains(q)
        }
    }

    var existingGroups: [TabGroup] {
        coordinator.groups
    }

    func groupSelected() {
        let chosen = items.filter { selection.contains($0.windowID) && !$0.isGrouped }
        guard chosen.count >= 2 else { return }
        if let target = targetExistingGroup {
            for item in chosen {
                coordinator.add(windowID: item.windowID, pid: item.pid, to: target)
            }
        } else {
            let name = groupName.isEmpty ? nil : groupName
            _ = coordinator.createGroup(name: name, windowIDs: chosen.map { (id: $0.windowID, pid: $0.pid) })
        }
    }
}

struct WindowPickerView: View {
    @ObservedObject var model: PickerModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search windows…", text: $model.search)
                .textFieldStyle(.roundedBorder)

            List(model.filtered, id: \.id, selection: $model.selection) { item in
                HStack(spacing: 8) {
                    Image(nsImage: item.icon).resizable().frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).lineLimit(1).truncationMode(.tail)
                        Text(item.appName).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.isGrouped {
                        Text("grouped").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .tag(item.windowID)
            }

            HStack {
                TextField("Group name (optional)", text: $model.groupName)
                    .textFieldStyle(.roundedBorder)
                if !model.existingGroups.isEmpty {
                    Picker("Add to", selection: $model.targetExistingGroup) {
                        Text("New group").tag(UUID?.none)
                        ForEach(model.existingGroups) { g in
                            Text(g.name).tag(UUID?.some(g.id))
                        }
                    }
                    .frame(width: 180)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onDone() }.keyboardShortcut(.cancelAction)
                Button("Group \(model.selection.count) windows") {
                    model.groupSelected()
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.selection.isEmpty ||
                    (model.targetExistingGroup == nil &&
                     model.selection.filter { id in
                         !(model.items.first(where: { $0.windowID == id })?.isGrouped ?? false)
                     }.count < 2)
                )
            }
        }
        .padding(12)
        .frame(width: 560, height: 420)
    }
}
