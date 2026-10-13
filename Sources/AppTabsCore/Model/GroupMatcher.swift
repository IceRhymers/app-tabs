import Foundation

/// Matches persisted groups against currently-open windows on restore.
public enum GroupMatcher {
    /// Given a saved group and the set of currently open windows, returns a restored
    /// member list (order preserved from the saved group) containing members whose
    /// windows are still open. Per-tab fields (color, custom name) are carried over
    /// from the saved member onto the matched window.
    public static func restore(members saved: [GroupMember], open: [GroupMember]) -> [GroupMember] {
        var pool = open
        var out: [GroupMember] = []
        for savedMember in saved {
            // 1) Same window still alive (same CGWindowID — common when AppTabs restarts)
            if let idx = pool.firstIndex(where: { $0.windowID == savedMember.windowID }) {
                out.append(carried(savedMember, onto: pool.remove(at: idx)))
                continue
            }
            // 2) Same app + same title (app relaunched, window re-created)
            if let idx = pool.firstIndex(where: {
                $0.bundleIdentifier == savedMember.bundleIdentifier &&
                $0.windowTitle == savedMember.windowTitle
            }) {
                out.append(carried(savedMember, onto: pool.remove(at: idx)))
                continue
            }
            // 3) Same app, single open window of that app
            let sameApp = pool.enumerated().filter { $0.element.bundleIdentifier == savedMember.bundleIdentifier }
            if sameApp.count == 1 {
                out.append(carried(savedMember, onto: pool.remove(at: sameApp[0].offset)))
                continue
            }
        }
        return out
    }

    /// Restores saved per-tab state (color, custom name) onto the matched open window.
    private static func carried(_ saved: GroupMember, onto open: GroupMember) -> GroupMember {
        var m = open
        m.colorID = saved.colorID
        m.customTitle = saved.customTitle
        return m
    }
}
