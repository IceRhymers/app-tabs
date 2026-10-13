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
        case titleChanged(pid: pid_t, windowID: CGWindowID, title: String)
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
    /// Windows subscribed to kAXTitleChangedNotification individually (grouped tabs only),
    /// so app-wide title churn never reaches us.
    private var titleWatched: [CGWindowID: AXUIElement] = [:]
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
        // Title changes are subscribed per window (see watchTitle), not app-wide:
        // many apps retitle constantly (tabs, web content), and each notification
        // costs cross-process reads on the main thread.
    }

    /// Subscribes title-change notifications for one window (a grouped tab).
    /// No-op if already watched, the app isn't watched, or the element isn't a window.
    public func watchTitle(pid: pid_t, windowID: CGWindowID, element: AXUIElement) {
        guard titleWatched[windowID] == nil else { return }
        guard let entry = observers[pid] else { return }
        let t0 = Perf.enabled ? CFAbsoluteTimeGetCurrent() : 0
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id == windowID else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(entry.observer, element, kAXTitleChangedNotification as CFString, context)
        guard err == .success else { return }
        titleWatched[windowID] = element
        // NOTE: no AXUIElementSetMessagingTimeout here. This element is the same
        // cached element the coordinator calls raise()/frame on during tab switches;
        // a short timeout would leak onto that foreground path and add ~250ms stalls.
        if Perf.enabled { Perf.log("hub.watchTitle add", (CFAbsoluteTimeGetCurrent() - t0) * 1000, detail: "pid=\(pid) win=\(windowID)") }
    }

    public func unwatchTitle(windowID: CGWindowID) {
        guard let element = titleWatched.removeValue(forKey: windowID) else { return }
        // AXObserver has no per-notification removal; remove/re-add the observer's
        // notifications would be heavier than leaving the dead subscription, so we
        // just stop tracking and filter any late events by grouped-ness downstream.
        _ = element
    }

    public func unwatchAllTitles(pid: pid_t) {
        for (windowID, element) in titleWatched {
            var p: pid_t = 0
            AXUIElementGetPid(element, &p)
            if p == pid { titleWatched.removeValue(forKey: windowID) }
        }
    }

    public func unwatch(pid: pid_t) {
        guard let entry = observers.removeValue(forKey: pid) else { return }
        unwatchAllTitles(pid: pid)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), entry.runLoopSource, .defaultMode)
    }

    public func stopAll() {
        for (_, entry) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), entry.runLoopSource, .defaultMode)
        }
        observers.removeAll()
        titleWatched.removeAll()
    }

    private func handleNotification(name: String, element: AXUIElement) {
        let t0 = Perf.enabled ? CFAbsoluteTimeGetCurrent() : 0
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let event: Event
        switch name {
        case kAXWindowCreatedNotification: event = .windowCreated(pid: pid)
        case kAXUIElementDestroyedNotification: event = .windowDestroyed(pid: pid)
        case kAXMovedNotification: event = .windowMoved(pid: pid)
        case kAXResizedNotification: event = .windowResized(pid: pid)
        case kAXFocusedWindowChangedNotification: event = .focusedWindowChanged(pid: pid)
        case kAXTitleChangedNotification:
            let t0 = Perf.enabled ? CFAbsoluteTimeGetCurrent() : 0
            var windowID: CGWindowID = 0
            let axErr = _AXUIElementGetWindow(element, &windowID)
            guard axErr == .success, windowID != 0 else { return }
            guard titleWatched[windowID] != nil else { return } // dead subscription / ungrouped
            // Scope a short timeout to just this title read so a slow app can't stall
            // the main thread — then restore the default so foreground ops on the same
            // element (raise/frame during tab switches) are unaffected.
            AXUIElementSetMessagingTimeout(element, 0.15)
            var value: CFTypeRef?
            let readErr = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
            AXUIElementSetMessagingTimeout(element, 0) // 0 = system default
            guard readErr == .success, let title = value as? String else { return }
            if Perf.enabled {
                Perf.log("hub.title AX reads", (CFAbsoluteTimeGetCurrent() - t0) * 1000, detail: "pid=\(pid) win=\(windowID)")
            }
            event = .titleChanged(pid: pid, windowID: windowID, title: title)
        default: return
        }
        // AXObserver callbacks already run on the main run loop (we add the source to
        // CFRunLoopGetMain), so invoke the handler directly instead of hopping queues.
        if Perf.enabled {
            Perf.log("hub.\(name)", (CFAbsoluteTimeGetCurrent() - t0) * 1000, detail: "pid=\(pid)")
        }
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
