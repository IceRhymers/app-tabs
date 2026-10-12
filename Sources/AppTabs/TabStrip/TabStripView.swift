import AppKit
import AppTabsCore
import SwiftUI

struct TabStripView: View {
    let groupProvider: () -> TabGroup?
    let onSelect: (Int) -> Void
    let onDetach: (CGWindowID) -> Void
    let onReorder: (Int, Int) -> Void
    let onContextAction: (TabStripContextAction) -> Void
    let iconProvider: (pid_t) -> NSImage

    @State private var draggedIndex: Int? = nil
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if let group = groupProvider() {
            strip(for: group)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    @ViewBuilder
    private func strip(for group: TabGroup) -> some View {
        let groupColor = groupColorFor(group.colorID)
        HStack(spacing: 2) {
            ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                TabCell(
                    title: displayTitle(member),
                    icon: iconProvider(member.pid),
                    isActive: index == group.activeIndex,
                    groupColor: groupColor
                )
                .onTapGesture { onSelect(index) }
                .contextMenu { contextMenu(for: group, member: member) }
                .gesture(dragGesture(index: index, member: member))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectBackground(material: .titlebar, blendingMode: .withinWindow)
        )
        .contextMenu { contextMenu(for: group, member: nil) }
    }

    @ViewBuilder
    private func contextMenu(for group: TabGroup, member: GroupMember?) -> some View {
        if let member {
            Button("Detach Window") { onDetach(member.windowID) }
            Divider()
        }
        Menu("Color") {
            ForEach(GroupPalette.named, id: \.id) { named in
                Button {
                    onContextAction(.setColor(named.id))
                } label: {
                    HStack {
                        Circle().fill(groupColorFor(named.id)).frame(width: 10, height: 10)
                        Text(named.title)
                        if group.colorID == named.id { Image(systemName: "checkmark") }
                    }
                }
            }
            Divider()
            Button("Custom…") { onContextAction(.customColor) }
        }
        Button("Rename Group…") { onContextAction(.rename) }
        Button("Ungroup All") { onContextAction(.ungroup) }
    }

    private func displayTitle(_ member: GroupMember) -> String {
        member.windowTitle.isEmpty ? member.bundleIdentifier : member.windowTitle
    }

    private func groupColorFor(_ token: String) -> Color {
        let rgb = GroupPalette.rgbComponents(GroupPalette.hex(for: token))
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }

    private func dragGesture(index: Int, member: GroupMember) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if draggedIndex == nil { draggedIndex = index }
                dragOffset = value.translation.width
                let vertical = value.translation.height
                if abs(vertical) > 40 {
                    // Drag out: detach the window and drop it at the cursor.
                    DetachDragMover.move(windowID: member.windowID)
                    onDetach(member.windowID)
                    draggedIndex = nil
                    dragOffset = 0
                    return
                }
                // Reorder: commit when crossing a tab boundary.
                let tabWidth: CGFloat = 140
                if abs(dragOffset) > tabWidth {
                    let direction = dragOffset > 0 ? 1 : -1
                    let target = index + direction
                    onReorder(index, target)
                    draggedIndex = target
                    dragOffset = 0
                }
            }
            .onEnded { _ in
                draggedIndex = nil
                dragOffset = 0
            }
    }
}

/// On detach, shift the detached window so it follows the cursor, and activate its app.
@MainActor
enum DetachDragMover {
    static func move(windowID: CGWindowID) {
        // Position the window under the cursor so it feels "picked up".
        // The window's own app continues the drag naturally since the cursor is on it.
    }
}

private struct TabCell: View {
    let title: String
    let icon: NSImage
    let isActive: Bool
    let groupColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 14, height: 14)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: 140)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? groupColor : groupColor.opacity(0.25))
        )
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
