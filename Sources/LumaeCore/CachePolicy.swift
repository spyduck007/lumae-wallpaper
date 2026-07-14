import Foundation

public struct CacheEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var sizeBytes: Int64
    public var lastAccessed: Date
    public var isPinned: Bool

    public init(path: String, sizeBytes: Int64, lastAccessed: Date, isPinned: Bool = false) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.lastAccessed = lastAccessed
        self.isPinned = isPinned
    }
}

public enum CachePolicy {
    public static func evictionCandidates(entries: [CacheEntry], limitBytes: Int64) -> [CacheEntry] {
        guard limitBytes >= 0 else { return entries.filter { !$0.isPinned } }
        var currentSize = entries.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
        guard currentSize > limitBytes else { return [] }

        var result: [CacheEntry] = []
        for entry in entries.filter({ !$0.isPinned }).sorted(by: { $0.lastAccessed < $1.lastAccessed }) {
            guard currentSize > limitBytes else { break }
            result.append(entry)
            currentSize -= max(0, entry.sizeBytes)
        }
        return result
    }
}
