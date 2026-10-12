import Foundation

/// Persists groups to ~/Library/Application Support/AppTabs/groups.json
public struct GroupStore {
    public struct Snapshot: Codable {
        public var groups: [TabGroup]
        public var savedAt: Date
    }

    public let url: URL

    public init(directory: URL? = nil) {
        if let directory {
            url = directory.appendingPathComponent("groups.json")
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            url = base.appendingPathComponent("AppTabs/groups.json")
        }
    }

    public func save(groups: [TabGroup]) throws {
        let snapshot = Snapshot(groups: groups, savedAt: Date())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public func load() throws -> [TabGroup] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Snapshot.self, from: data).groups
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
