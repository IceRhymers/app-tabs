import Foundation
import AppTabsCore

@main
struct TestRunner {
    @MainActor
    static func main() {
        print("AppTabsCore tests")
        windowGroupTests()
        groupStoreTests()
        groupMatcherTests()
        frameMathTests()
        exit(Check.finish())
    }
}

private func member(_ num: UInt32) -> GroupMember {
    GroupMember(windowID: num, bundleIdentifier: "com.test.\(num)", windowTitle: "W\(num)", pid: 1000 + Int32(num))
}

@MainActor private func windowGroupTests() {
    print("TabGroup model")
    var g = TabGroup(name: "T", members: [member(1), member(2), member(3)], activeIndex: 2, frame: .zero)

    g.setActive(3)
    Check.equal(g.activeIndex, 2, "setActive finds index")
    Check.equal(g.activeMember?.windowID ?? 0, 3, "activeMember resolves")

    Check.expect(g.remove(3), "remove returns true")
    Check.equal(g.activeIndex, 1, "remove adjusts activeIndex")

    var g2 = TabGroup(name: "T", members: [member(1), member(2), member(3)], frame: .zero)
    g2.move(from: 0, to: 2)
    Check.equal(g2.members.map(\.windowID), [2, 3, 1], "move reorders")
}

@MainActor private func groupStoreTests() {
    print("GroupStore persistence")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = GroupStore(directory: dir)

    let g = TabGroup(name: "GD1", members: [
        GroupMember(windowID: 42, bundleIdentifier: "com.apple.Terminal", windowTitle: "zsh", pid: 123),
        GroupMember(windowID: 43, bundleIdentifier: "com.apple.Safari", windowTitle: "Docs", pid: 124),
    ], activeIndex: 1, frame: CGRect(x: 10, y: 20, width: 800, height: 600))

    do {
        try store.save(groups: [g])
        let loaded = try store.load()
        Check.equal(loaded.count, 1, "round trip count")
        Check.equal(loaded.first?.name ?? "", "GD1", "round trip name")
        Check.equal(loaded.first?.members.count ?? 0, 2, "round trip members")
        Check.equal(loaded.first?.activeIndex ?? -1, 1, "round trip activeIndex")
        Check.expect(loaded.first?.frame == g.frame, "round trip frame")
    } catch {
        Check.expect(false, "save/load threw: \(error)")
    }

    let emptyStore = GroupStore(directory: dir.appendingPathComponent("missing"))
    do {
        Check.expect(try emptyStore.load().isEmpty, "missing file loads empty")
    } catch {
        Check.expect(false, "load threw on missing file")
    }
}

@MainActor private func groupMatcherTests() {
    print("GroupMatcher restore")
    func m(_ num: UInt32, _ bundle: String, _ title: String) -> GroupMember {
        GroupMember(windowID: num, bundleIdentifier: bundle, windowTitle: title, pid: 1000)
    }

    let saved = [m(1, "a", "t1"), m(2, "b", "t2")]
    let open = [m(2, "b", "t2"), m(1, "a", "t1")]
    Check.equal(GroupMatcher.restore(members: saved, open: open).map(\.windowID), [1, 2], "matches by windowID")

    let open2 = [m(90, "b", "t2"), m(91, "a", "t1")]
    Check.equal(GroupMatcher.restore(members: saved, open: open2).map(\.windowID), [91, 90], "matches by bundle+title")

    let saved3 = [m(1, "a", "Old"), m(2, "b", "Keep")]
    let open3 = [m(50, "a", "New"), m(60, "b", "Keep")]
    Check.equal(GroupMatcher.restore(members: saved3, open: open3).map(\.windowID), [50, 60], "falls back to single window of app")

    let saved4 = [m(1, "a", "t1"), m(2, "b", "t2"), m(3, "c", "gone")]
    let open4 = [m(1, "a", "t1"), m(2, "b", "t2")]
    Check.equal(GroupMatcher.restore(members: saved4, open: open4).map(\.windowID), [1, 2], "drops unmatched members")
}

@MainActor
private func frameMathTests() {
    print("FrameMath")
    NSScreenPrimaryHeightProvider.height = 1000

    let ax = CGRect(x: 10, y: 100, width: 200, height: 300)
    let appkit = FrameMath.axToAppKit(ax, screenFrame: .zero)
    Check.equal(appkit.origin.y, 600, "AX→AppKit flips y")
    Check.equal(appkit.size, ax.size, "size preserved")

    // Window top area: AX y=200, height 500 → AppKit y=300, maxY=800; visible 980 → 180 room ≥ 28 → above.
    let strip1 = FrameMath.stripFrame(
        forWindowFrame: CGRect(x: 0, y: 200, width: 800, height: 500),
        screenVisibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 980),
        screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000))
    Check.equal(strip1.origin.y, 800, "strip above window when room")
    Check.equal(strip1.height, FrameMath.stripHeight, "strip height")

    // Window at very top: AX y=0 → AppKit maxY=1000 > visible 980 → overlay inside window.
    let strip2 = FrameMath.stripFrame(
        forWindowFrame: CGRect(x: 0, y: 0, width: 800, height: 500),
        screenVisibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 980),
        screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1000))
    Check.equal(strip2.origin.y, 1000 - FrameMath.stripHeight, "strip overlays when no room")
}
