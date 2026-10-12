import Foundation

/// Named group colors. A group stores either one of these ids or a custom hex string ("#RRGGBB").
public enum GroupPalette {
    public struct NamedColor: Equatable, Sendable {
        public let id: String
        public let title: String
        public let hex: String // "#RRGGBB"
    }

    public static let named: [NamedColor] = [
        .init(id: "blue", title: "Blue", hex: "#3B82F6"),
        .init(id: "purple", title: "Purple", hex: "#8B5CF6"),
        .init(id: "pink", title: "Pink", hex: "#EC4899"),
        .init(id: "red", title: "Red", hex: "#EF4444"),
        .init(id: "orange", title: "Orange", hex: "#F97316"),
        .init(id: "yellow", title: "Yellow", hex: "#EAB308"),
        .init(id: "green", title: "Green", hex: "#22C55E"),
        .init(id: "teal", title: "Teal", hex: "#14B8A6"),
        .init(id: "indigo", title: "Indigo", hex: "#6366F1"),
        .init(id: "graphite", title: "Graphite", hex: "#6B7280"),
    ]

    /// A random named color not already used by another group.
    /// If every named color is taken, picks among the least-used ones.
    public static func pickUnused<R: RandomNumberGenerator>(existing: [String], using rng: inout R) -> String {
        let used = Set(existing)
        let unused = named.map(\.id).filter { !used.contains($0) }
        if let pick = unused.randomElement(using: &rng) { return pick }
        // All taken: pick among the least-used ids.
        var counts: [String: Int] = [:]
        for id in existing { counts[id, default: 0] += 1 }
        let min = counts.values.min() ?? 0
        let least = named.map(\.id).filter { (counts[$0] ?? 0) == min }
        return least.randomElement(using: &rng) ?? named[0].id
    }

    /// Resolve a stored color token (named id or "#RRGGBB") to its hex string.
    public static func hex(for token: String) -> String {
        if let found = named.first(where: { $0.id == token }) { return found.hex }
        if token.hasPrefix("#"), token.count == 7 { return token }
        return named[0].hex
    }

    /// Parse "#RRGGBB" to (r, g, b) in 0...1.
    public static func rgbComponents(_ hex: String) -> (r: Double, g: Double, b: Double) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return (0.23, 0.51, 0.96) }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}
