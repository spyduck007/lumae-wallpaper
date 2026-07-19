import Foundation

public enum PlaylistTarget: Codable, Hashable, Sendable {
    case currentPresentation
    case display(DisplayFingerprint)
}

public struct WallpaperPlaylist: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var wallpaperIDs: [UUID]
    public var intervalSeconds: TimeInterval
    public var shuffle: Bool
    public var isRunning: Bool
    public var cursor: Int
    public var currentWallpaperID: UUID?
    public var history: [UUID]
    public var target: PlaylistTarget
    public var lastAdvancedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String = "New Playlist",
        wallpaperIDs: [UUID] = [],
        intervalSeconds: TimeInterval = 900,
        shuffle: Bool = false,
        isRunning: Bool = false,
        cursor: Int = 0,
        currentWallpaperID: UUID? = nil,
        history: [UUID] = [],
        target: PlaylistTarget = .currentPresentation,
        lastAdvancedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.wallpaperIDs = wallpaperIDs
        self.intervalSeconds = intervalSeconds
        self.shuffle = shuffle
        self.isRunning = isRunning
        self.cursor = cursor
        self.currentWallpaperID = currentWallpaperID
        self.history = history
        self.target = target
        self.lastAdvancedAt = lastAdvancedAt
    }
}

public enum PlaylistDirection {
    case previous
    case next
}

public enum WallpaperPlaylistEngine {
    public static func advance(
        playlist: inout WallpaperPlaylist,
        direction: PlaylistDirection,
        availableIDs: Set<UUID>,
        randomIndex: ((Int) -> Int)? = nil
    ) -> UUID? {
        let eligible = playlist.wallpaperIDs.filter(availableIDs.contains)
        guard !eligible.isEmpty else { return nil }

        switch direction {
        case .previous:
            while let candidate = playlist.history.popLast() {
                guard eligible.contains(candidate) else { continue }
                playlist.currentWallpaperID = candidate
                if let index = eligible.firstIndex(of: candidate) {
                    playlist.cursor = (index + 1) % eligible.count
                }
                playlist.lastAdvancedAt = Date()
                return candidate
            }
            let fallback = playlist.currentWallpaperID.flatMap { eligible.contains($0) ? $0 : nil }
                ?? eligible.first
            playlist.currentWallpaperID = fallback
            return fallback

        case .next:
            if let current = playlist.currentWallpaperID {
                playlist.history.append(current)
                if playlist.history.count > 100 {
                    playlist.history.removeFirst(playlist.history.count - 100)
                }
            }

            let next: UUID
            if playlist.shuffle {
                let candidates = eligible.count > 1
                    ? eligible.filter { $0 != playlist.currentWallpaperID }
                    : eligible
                let pool = candidates.isEmpty ? eligible : candidates
                let pick = randomIndex?(pool.count)
                    ?? Int.random(in: 0..<pool.count)
                next = pool[min(max(pick, 0), pool.count - 1)]
            } else {
                let index = ((playlist.cursor % eligible.count) + eligible.count) % eligible.count
                next = eligible[index]
                playlist.cursor = (index + 1) % eligible.count
            }

            playlist.currentWallpaperID = next
            playlist.lastAdvancedAt = Date()
            return next
        }
    }
}
