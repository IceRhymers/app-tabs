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
        groupPaletteTests()
        tabRenameTests()
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

    // Saved per-tab fields (color, custom name) survive all match paths.
    var savedCustom1 = m(1, "a", "t1"); savedCustom1.colorID = "teal"; savedCustom1.customTitle = "Docs"
    var savedCustom2 = m(2, "b", "t2"); savedCustom2.colorID = "#ABCDEF"; savedCustom2.customTitle = "Mail"

    let restoredSame = GroupMatcher.restore(members: [savedCustom1, savedCustom2], open: [m(1, "a", "t1"), m(2, "b", "t2")])
    Check.equal(restoredSame[0].colorID, "teal", "same-window match keeps color")
    Check.equal(restoredSame[0].customTitle ?? "", "Docs", "same-window match keeps custom title")
    Check.equal(restoredSame[1].customTitle ?? "", "Mail", "second member keeps custom title")

    let openRelaunched = [m(90, "b", "t2"), m(91, "a", "t1")]
    let restoredRelaunch = GroupMatcher.restore(members: [savedCustom1, savedCustom2], open: openRelaunched)
    Check.equal(restoredRelaunch[0].customTitle ?? "", "Docs", "bundle+title match keeps custom title")
    Check.equal(restoredRelaunch[0].colorID, "teal", "bundle+title match keeps color")

    let openSingle = [m(50, "a", "New"), m(60, "b", "Other")]
    let restoredSingle = GroupMatcher.restore(members: [savedCustom1, savedCustom2], open: openSingle)
    Check.equal(restoredSingle[0].customTitle ?? "", "Docs", "single-window match keeps custom title")
    Check.equal(restoredSingle[0].colorID, "teal", "single-window match keeps color")
}

@MainActor private func tabRenameTests() {
    print("Tab rename")
    var tab = GroupMember(windowID: 1, bundleIdentifier: "com.apple.Safari", windowTitle: "Docs", pid: 1)

    // displayTitle precedence: custom → window title → bundle id.
    Check.equal(tab.displayTitle, "Docs", "displayTitle uses window title by default")
    tab.setCustomTitle("Work")
    Check.equal(tab.displayTitle, "Work", "custom title wins")
    Check.expect(tab.customTitle == "Work", "custom title stored trimmed")

    tab.setCustomTitle("   ")
    Check.expect(tab.customTitle == nil, "blank custom title clears to nil")
    Check.equal(tab.displayTitle, "Docs", "cleared tab falls back to window title")

    tab.setCustomTitle("  Padded  ")
    Check.equal(tab.customTitle ?? "", "Padded", "custom title is trimmed")
    tab.setCustomTitle("")
    Check.expect(tab.customTitle == nil, "empty custom title clears to nil")

    tab.windowTitle = ""
    Check.equal(tab.displayTitle, "com.apple.Safari", "no title falls back to bundle id")

    // setCustomTitle on the group mutates the right member.
    var g = TabGroup(name: "T", members: [member(1), member(2), member(3)], frame: .zero)
    g.setCustomTitle("First", forMember: 2)
    Check.equal(g.members[1].customTitle ?? "", "First", "group setCustomTitle targets member")
    g.setCustomTitle("", forMember: 2)
    Check.expect(g.members[1].customTitle == nil, "group setCustomTitle clears member")

    // displayTitle survives a save/load round trip.
    g.members[0].setCustomTitle("Renamed")
    g.members[1].colorID = "#556677"
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = GroupStore(directory: dir)
    do {
        try store.save(groups: [g])
        let loaded = try store.load()
        Check.equal(loaded.first?.members[0].customTitle ?? "", "Renamed", "custom title round trip")
        Check.expect(loaded.first?.members[2].customTitle == nil, "untitled member stays nil")
    } catch {
        Check.expect(false, "rename round trip threw: \(error)")
    }

    // Pre-customTitle groups.json decodes with customTitle == nil.
    let legacyJSON = """
    {
      "activeIndex": 0,
      "frame": [[10, 20], [800, 600]],
      "id": "00000000-0000-0000-0000-000000000002",
      "members": [
        {"windowID": 42, "bundleIdentifier": "com.a", "windowTitle": "A", "pid": 1}
      ],
      "name": "Old"
    }
    """.data(using: .utf8)!
    do {
        let decoded = try JSONDecoder().decode(TabGroup.self, from: legacyJSON)
        Check.expect(decoded.members[0].customTitle == nil, "legacy decode leaves customTitle nil")
        Check.equal(decoded.members[0].displayTitle, "A", "legacy member displays window title")
    } catch {
        Check.expect(false, "legacy customTitle decode threw: \(error)")
    }
}

@MainActor private func groupPaletteTests() {
    print("GroupPalette")
    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    var rng = SeededRNG(seed: 42)
    let allNamed = GroupPalette.named.map(\.id)

    // With nothing used, pick is one of the named ids.
    let first = GroupPalette.pickUnused(existing: [], using: &rng)
    Check.expect(allNamed.contains(first), "first pick is a named color")

    // Simulate N groups each receiving a color: all distinct until palette exhausts.
    var taken: [String] = []
    for _ in 0..<allNamed.count {
        taken.append(GroupPalette.pickUnused(existing: taken, using: &rng))
    }
    Check.equal(Set(taken).count, allNamed.count, "picks cover palette without repeats")

    // With all colors taken, falls back to least-used (still a valid named id).
    let fallback = GroupPalette.pickUnused(existing: taken, using: &rng)
    Check.expect(allNamed.contains(fallback), "fallback is a named color")
    Check.expect(taken.filter { $0 == fallback }.count <= 1, "fallback picks least-used")

    // hex resolution
    Check.equal(GroupPalette.hex(for: "blue"), "#3B82F6", "named id resolves to hex")
    Check.equal(GroupPalette.hex(for: "#A1B2C3"), "#A1B2C3", "custom hex passes through")
    Check.equal(GroupPalette.hex(for: "bogus"), GroupPalette.named[0].hex, "unknown falls back to first")

    // rgb parsing
    let rgb = GroupPalette.rgbComponents("#FF8000")
    Check.equal(rgb.r, 1.0, "red component")
    Check.equal(rgb.g, 128.0 / 255.0, "green component")
    Check.equal(rgb.b, 0.0, "blue component")

    // Legacy groups.json (no member colorID) still decodes.
    let legacyJSON = """
    {
      "activeIndex": 0,
      "frame": [[10, 20], [800, 600]],
      "id": "00000000-0000-0000-0000-000000000001",
      "members": [
        {"windowID": 42, "bundleIdentifier": "com.a", "windowTitle": "A", "pid": 1},
        {"windowID": 43, "bundleIdentifier": "com.b", "windowTitle": "B", "pid": 2}
      ],
      "name": "Old",
      "parksInactiveWindows": false,
      "colorID": "red"
    }
    """.data(using: .utf8)!
    do {
        let decoded = try JSONDecoder().decode(TabGroup.self, from: legacyJSON)
        Check.equal(decoded.name, "Old", "legacy name preserved")
        Check.equal(decoded.members.count, 2, "legacy members decode")
        Check.equal(decoded.members[0].colorID, "red", "legacy group color folds into members")
    } catch {
        Check.expect(false, "legacy decode threw: \(error)")
    }

    // Per-tab colorID survives a save/load round trip.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = GroupStore(directory: dir)
    let g = TabGroup(name: "C", members: [
        GroupMember(windowID: 1, bundleIdentifier: "a", windowTitle: "A", pid: 1, colorID: "#123456"),
        GroupMember(windowID: 2, bundleIdentifier: "b", windowTitle: "B", pid: 2, colorID: "teal"),
    ], frame: .zero)
    do {
        try store.save(groups: [g])
        let loaded = try store.load()
        Check.equal(loaded.first?.members[0].colorID ?? "", "#123456", "member 1 color round trip")
        Check.equal(loaded.first?.members[1].colorID ?? "", "teal", "member 2 color round trip")
    } catch {
        Check.expect(false, "color round trip threw: \(error)")
    }
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
