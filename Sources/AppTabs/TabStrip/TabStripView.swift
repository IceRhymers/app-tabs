import AppKit
import AppTabsCore
import SwiftUI

/// A floating cluster of tabs that hovers on the window's top edge.
/// Centered by default; grows outward as tabs are added up to the window width,
/// then scrolls. No full-width bar.
struct TabStripView: View {
    static let tabWidth: CGFloat = 140
    static let tabSpacing: CGFloat = 2
    static let horizontalPadding: CGFloat = 4

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

    /// Total width the tab row wants before scrolling.
    static func contentWidth(tabCount: Int) -> CGFloat {
        CGFloat(tabCount) * tabWidth + CGFloat(max(0, tabCount - 1)) * tabSpacing + horizontalPadding * 2
    }

    @ViewBuilder
    private func strip(for group: TabGroup) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.tabSpacing) {
                    ForEach(Array(group.members.enumerated()), id: \.element.id) { index, member in
                        TabCell(
                            title: displayTitle(member),
                            icon: iconProvider(member.pid),
                            isActive: index == group.activeIndex,
                            tabColor: groupColorFor(member.colorID)
                        )
                        .id(member.windowID)
                        .frame(width: Self.tabWidth)
                        .onTapGesture { onSelect(index) }
                        .contextMenu { contextMenu(for: group, member: member) }
                        .gesture(dragGesture(index: index, member: member))
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
            }
            .scrollClipDisabled()
            .onChange(of: group.activeIndex) { _, newIndex in
                guard group.members.indices.contains(newIndex) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(group.members[newIndex].windowID, anchor: .center)
                }
            }
            .onChange(of: group.members.count) { _, _ in
                // Keep the active tab visible as tabs come and go.
                if let active = group.activeMember {
                    proxy.scrollTo(active.windowID, anchor: .center)
                }
            }
        }
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        )
        .contextMenu { contextMenu(for: group, member: nil) }
    }

    @ViewBuilder
    private func contextMenu(for group: TabGroup, member: GroupMember?) -> some View {
        if let member {
            Menu("Tab Color") {
                ForEach(GroupPalette.named, id: \.id) { named in
                    Button {
                        onContextAction(.setTabColor(member.windowID, named.id))
                    } label: {
                        HStack {
                            Circle().fill(groupColorFor(named.id)).frame(width: 10, height: 10)
                            Text(named.title)
                            if member.colorID == named.id { Image(systemName: "checkmark") }
                        }
                    }
                }
                Divider()
                Button("Custom…") { onContextAction(.customTabColor(member.windowID)) }
            }
            Button("Detach Window") { onDetach(member.windowID) }
            Divider()
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
                    // Drag out: detach.
                    onDetach(member.windowID)
                    draggedIndex = nil
                    dragOffset = 0
                    return
                }
                // Reorder: commit when crossing a tab boundary.
                let tabWidth = Self.tabWidth
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

private struct TabCell: View {
    let title: String
    let icon: NSImage
    let isActive: Bool
    let tabColor: Color

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
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? tabColor : tabColor.opacity(0.25))
        )
    }
}
