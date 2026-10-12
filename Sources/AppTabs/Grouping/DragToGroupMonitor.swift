import AppKit
import AppTabsCore

/// Detects "drag window A onto window B and hold" to group them.
/// Shows a blue outline after a short hover; grouping happens on mouse-up.
@MainActor
final class DragToGroupMonitor {
    private weak var coordinator: GroupCoordinator?
    private var monitor: Any?
    private var highlightPanel: NSPanel?

    /// CGWindowID of the window currently being dragged (heuristic: the focused window of the front app at drag start).
    private var draggedWindowID: CGWindowID?
    private var draggedPID: pid_t?
    private var isDragging = false
    private var hoverTarget: (windowID: CGWindowID, pid: pid_t, frame: CGRect)?
    private var hoverStart: Date?

    private let hoverDelay: TimeInterval = 0.5

    init(coordinator: GroupCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        // Global monitor receives events even when our app isn't active.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // Heuristic: the dragged window is the focused window of the app under the cursor.
            let p = NSEvent.mouseLocation
            if let info = WindowList.windowUnderPoint(p, excludingPIDs: [ProcessInfo.processInfo.processIdentifier]) {
                draggedWindowID = info.windowID
                draggedPID = info.pid
                isDragging = true
                hoverTarget = nil
                hoverStart = nil
            }
        case .leftMouseDragged:
            guard isDragging, let draggedID = draggedWindowID else { return }
            let p = NSEvent.mouseLocation
            guard let info = WindowList.windowUnderPoint(p, excludingPIDs: [ProcessInfo.processInfo.processIdentifier]) else {
                clearHover()
                return
            }
            if info.windowID == draggedID {
                clearHover()
                return
            }
            // New target?
            if hoverTarget?.windowID != info.windowID {
                hoverTarget = (info.windowID, info.pid, info.frame)
                hoverStart = Date()
                hideHighlight()
            }
            if let start = hoverStart, Date().timeIntervalSince(start) >= hoverDelay {
                showHighlight(frameAX: info.frame)
            }
        case .leftMouseUp:
            defer {
                isDragging = false
                draggedWindowID = nil
                hideHighlight()
            }
            guard let draggedID = draggedWindowID, let draggedPID,
                  let target = hoverTarget, let start = hoverStart,
                  Date().timeIntervalSince(start) >= hoverDelay,
                  draggedID != target.windowID else { return }
            group(dragged: (draggedID, draggedPID), onto: target)
        default:
            break
        }
    }

    private func group(dragged: (CGWindowID, pid_t), onto target: (windowID: CGWindowID, pid: pid_t, frame: CGRect)) {
        guard let coordinator else { return }
        // If target belongs to an existing group, add dragged into it. Otherwise create a new group.
        if let group = coordinator.groups.first(where: { $0.members.contains(where: { $0.windowID == target.windowID }) }) {
            coordinator.add(windowID: dragged.0, pid: dragged.1, to: group.id)
        } else {
            _ = coordinator.createGroup(windowIDs: [
                (id: target.windowID, pid: target.pid),
                (id: dragged.0, pid: dragged.1),
            ])
        }
    }

    private func clearHover() {
        hoverTarget = nil
        hoverStart = nil
        hideHighlight()
    }

    // MARK: - Highlight overlay

    private func showHighlight(frameAX: CGRect) {
        let frame = FrameMath.axToAppKit(frameAX, screenFrame: .zero)
        let panel = highlightPanel ?? makeHighlightPanel()
        panel.setFrame(frame.insetBy(dx: -4, dy: -4), display: false)
        panel.contentView?.needsDisplay = true
        panel.orderFrontRegardless()
    }

    private func hideHighlight() {
        highlightPanel?.orderOut(nil)
    }

    private func makeHighlightPanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = HighlightView()
        highlightPanel = panel
        return panel
    }
}

private final class HighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 8, yRadius: 8)
        path.lineWidth = 4
        path.stroke()
        NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        path.fill()
    }
}
