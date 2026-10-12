import ApplicationServices
import Foundation

/// Watches AX notifications for a set of applications and reports events on the main actor.
/// Because AXObserver callbacks are C-level, we bridge through a small unmanaged context.
public final class AXObserverHub {
    public enum Event: Sendable {
        case windowCreated(pid: pid_t)
        case windowDestroyed(pid: pid_t)
        case windowMoved(pid: pid_t)
        case windowResized(pid: pid_t)
        case focusedWindowChanged(pid: pid_t)
        case appTerminated(pid: pid_t)
    }

    private final class AppObserver {
        let observer: AXObserver
        let runLoopSource: CFRunLoopSource
        init(observer: AXObserver, runLoopSource: CFRunLoopSource) {
            self.observer = observer
            self.runLoopSource = runLoopSource
        }
    }

    private var observers: [pid_t: AppObserver] = [:]
    private let handler: @Sendable (Event) -> Void

    public init(handler: @escaping @Sendable (Event) -> Void) {
        self.handler = handler
    }

    deinit {
        stopAll()
    }

    public func watch(pid: pid_t) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, element, notification, context in
            guard let context else { return }
            let hub = Unmanaged<AXObserverHub>.fromOpaque(context).takeUnretainedValue()
            let name = notification as String
            hub.handleNotification(name: name, element: element)
        }, &observer) == .success, let observer else { return }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        observers[pid] = AppObserver(observer: observer, runLoopSource: source)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let app = AXUIElementCreateApplication(pid)
        let notifications: [String] = [
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification,
            kAXMovedNotification,
            kAXResizedNotification,
            kAXFocusedWindowChangedNotification,
            kAXApplicationHiddenNotification,
        ]
        for name in notifications {
            AXObserverAddNotification(observer, app, name as CFString, context)
        }
    }

    public func unwatch(pid: pid_t) {
        guard let entry = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), entry.runLoopSource, .defaultMode)
    }

    public func stopAll() {
        for (pid, entry) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), entry.runLoopSource, .defaultMode)
            _ = pid
        }
        observers.removeAll()
    }

    private func handleNotification(name: String, element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let event: Event
        switch name {
        case kAXWindowCreatedNotification: event = .windowCreated(pid: pid)
        case kAXUIElementDestroyedNotification: event = .windowDestroyed(pid: pid)
        case kAXMovedNotification: event = .windowMoved(pid: pid)
        case kAXResizedNotification: event = .windowResized(pid: pid)
        case kAXFocusedWindowChangedNotification: event = .focusedWindowChanged(pid: pid)
        default: return
        }
        // AXObserver callbacks already run on the main run loop (we add the source to
        // CFRunLoopGetMain), so invoke the handler directly instead of hopping queues.
        let handler = self.handler
        if Thread.isMainThread {
            MainActor.assumeIsolated { handler(event) }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler(event) }
            }
        }
    }
}
