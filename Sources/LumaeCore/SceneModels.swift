import Foundation

public struct ScenePlaybackSettings: Codable, Hashable, Sendable {
    public var presentationMode: DisplayPresentationMode
    public var defaultScalingMode: WallpaperScalingMode
    public var videoQuality: VideoQuality
    public var maximumFrameRate: Int
    public var audioBehavior: AudioBehavior
    public var synchronizedDuplicatePlayback: Bool

    public init(
        presentationMode: DisplayPresentationMode,
        defaultScalingMode: WallpaperScalingMode,
        videoQuality: VideoQuality,
        maximumFrameRate: Int,
        audioBehavior: AudioBehavior,
        synchronizedDuplicatePlayback: Bool
    ) {
        self.presentationMode = presentationMode
        self.defaultScalingMode = defaultScalingMode
        self.videoQuality = videoQuality
        self.maximumFrameRate = maximumFrameRate
        self.audioBehavior = audioBehavior
        self.synchronizedDuplicatePlayback = synchronizedDuplicatePlayback
    }
}

public struct SceneConfiguration: Codable, Hashable, Sendable {
    public var playback: ScenePlaybackSettings
    public var sharedWallpaperID: UUID?
    public var assignments: [DisplayAssignment]
    public var playlists: [WallpaperPlaylist]
    public var activePlaylistID: UUID?
    public var widgets: [DesktopWidget]
    public var widgetDisplayMode: WidgetDisplayMode
    public var widgetDisplayConfigurations: [WidgetDisplayConfiguration]
    public var widgetPerDisplayInitialized: Bool
    public var defaultWidgetStyle: WidgetVisualStyle

    public init(
        playback: ScenePlaybackSettings,
        sharedWallpaperID: UUID?,
        assignments: [DisplayAssignment],
        playlists: [WallpaperPlaylist],
        activePlaylistID: UUID?,
        widgets: [DesktopWidget],
        widgetDisplayMode: WidgetDisplayMode,
        widgetDisplayConfigurations: [WidgetDisplayConfiguration],
        widgetPerDisplayInitialized: Bool,
        defaultWidgetStyle: WidgetVisualStyle
    ) {
        self.playback = playback
        self.sharedWallpaperID = sharedWallpaperID
        self.assignments = assignments
        self.playlists = playlists
        self.activePlaylistID = activePlaylistID
        self.widgets = widgets
        self.widgetDisplayMode = widgetDisplayMode
        self.widgetDisplayConfigurations = widgetDisplayConfigurations
        self.widgetPerDisplayInitialized = widgetPerDisplayInitialized
        self.defaultWidgetStyle = defaultWidgetStyle
    }

    public var referencedWallpaperIDs: Set<UUID> {
        var result = Set(assignments.compactMap(\.wallpaperID))
        if let sharedWallpaperID {
            result.insert(sharedWallpaperID)
        }
        for playlist in playlists {
            result.formUnion(playlist.wallpaperIDs)
            if let currentWallpaperID = playlist.currentWallpaperID {
                result.insert(currentWallpaperID)
            }
        }
        return result
    }
}

public struct DesktopScene: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var configuration: SceneConfiguration
    public var createdAt: Date
    public var modifiedAt: Date
    public var lastActivatedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        configuration: SceneConfiguration,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        lastActivatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastActivatedAt = lastActivatedAt
    }
}
