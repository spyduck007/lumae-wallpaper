import Foundation

public enum WallpaperKind: String, Codable, CaseIterable, Sendable {
    case image
    case animatedImage
    case video
    case unsupported
}

public enum SupportedWallpaperFormat: String, Codable, CaseIterable, Sendable {
    case jpg, jpeg, png, heic, tiff, gif, mp4, mov, m4v

    public static func from(pathExtension: String) -> SupportedWallpaperFormat? {
        SupportedWallpaperFormat(rawValue: pathExtension.lowercased())
    }

    public var kind: WallpaperKind {
        switch self {
        case .jpg, .jpeg, .png, .heic, .tiff: return .image
        case .gif: return .animatedImage
        case .mp4, .mov, .m4v: return .video
        }
    }
}

public struct WallpaperMetadata: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var originalFilePath: String
    public var managedLibraryPath: String?
    public var format: SupportedWallpaperFormat
    public var fileSizeBytes: Int64
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var durationSeconds: Double?
    public var frameRate: Double?
    public var dateAdded: Date
    public var dateLastUsed: Date?
    public var tags: Set<String>
    public var category: String?
    public var isFavorite: Bool
    public var thumbnailPath: String?
    public var isMissing: Bool
    public var contentHash: String

    public init(
        id: UUID = UUID(),
        name: String,
        originalFilePath: String,
        managedLibraryPath: String? = nil,
        format: SupportedWallpaperFormat,
        fileSizeBytes: Int64,
        pixelWidth: Int,
        pixelHeight: Int,
        durationSeconds: Double? = nil,
        frameRate: Double? = nil,
        dateAdded: Date = Date(),
        dateLastUsed: Date? = nil,
        tags: Set<String> = [],
        category: String? = nil,
        isFavorite: Bool = false,
        thumbnailPath: String? = nil,
        isMissing: Bool = false,
        contentHash: String
    ) {
        self.id = id
        self.name = name
        self.originalFilePath = originalFilePath
        self.managedLibraryPath = managedLibraryPath
        self.format = format
        self.fileSizeBytes = fileSizeBytes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationSeconds = durationSeconds
        self.frameRate = frameRate
        self.dateAdded = dateAdded
        self.dateLastUsed = dateLastUsed
        self.tags = tags
        self.category = category
        self.isFavorite = isFavorite
        self.thumbnailPath = thumbnailPath
        self.isMissing = isMissing
        self.contentHash = contentHash
    }

    public var kind: WallpaperKind { format.kind }
    public var aspectRatio: Double {
        guard pixelHeight > 0 else { return 0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }
    public var effectiveFilePath: String { managedLibraryPath ?? originalFilePath }
}

public enum LibrarySortOrder: String, Codable, CaseIterable, Sendable {
    case dateAddedNewest
    case dateAddedOldest
    case nameAscending
    case nameDescending
    case recentlyUsed
    case fileSize
}

public struct LibraryFilter: Codable, Hashable, Sendable {
    public var query: String
    public var kinds: Set<WallpaperKind>
    public var category: String?
    public var requiredTags: Set<String>
    public var favoritesOnly: Bool
    public var missingOnly: Bool

    public init(
        query: String = "",
        kinds: Set<WallpaperKind> = [],
        category: String? = nil,
        requiredTags: Set<String> = [],
        favoritesOnly: Bool = false,
        missingOnly: Bool = false
    ) {
        self.query = query
        self.kinds = kinds
        self.category = category
        self.requiredTags = requiredTags
        self.favoritesOnly = favoritesOnly
        self.missingOnly = missingOnly
    }

    public func matches(_ wallpaper: WallpaperMetadata) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalizedQuery.isEmpty {
            let haystack = ([wallpaper.name, wallpaper.category ?? ""] + Array(wallpaper.tags))
                .joined(separator: " ")
                .lowercased()
            guard haystack.contains(normalizedQuery) else { return false }
        }
        if !kinds.isEmpty && !kinds.contains(wallpaper.kind) { return false }
        if let category, wallpaper.category != category { return false }
        if !requiredTags.isSubset(of: wallpaper.tags) { return false }
        if favoritesOnly && !wallpaper.isFavorite { return false }
        if missingOnly && !wallpaper.isMissing { return false }
        return true
    }
}

public enum WallpaperSorter {
    public static func sort(_ wallpapers: [WallpaperMetadata], by order: LibrarySortOrder) -> [WallpaperMetadata] {
        wallpapers.sorted { lhs, rhs in
            switch order {
            case .dateAddedNewest: return lhs.dateAdded > rhs.dateAdded
            case .dateAddedOldest: return lhs.dateAdded < rhs.dateAdded
            case .nameAscending: return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .nameDescending: return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            case .recentlyUsed: return (lhs.dateLastUsed ?? .distantPast) > (rhs.dateLastUsed ?? .distantPast)
            case .fileSize: return lhs.fileSizeBytes > rhs.fileSizeBytes
            }
        }
    }
}

public enum DuplicateDetector {
    public static func duplicate(of candidate: WallpaperMetadata, in library: [WallpaperMetadata]) -> WallpaperMetadata? {
        library.first { $0.contentHash == candidate.contentHash && $0.id != candidate.id }
    }
}
