import Foundation

public enum ImportBehavior: String, Codable, CaseIterable, Sendable {
    case referenceOriginal
    case copyToManagedLibrary
}

public enum AudioBehavior: String, Codable, CaseIterable, Sendable {
    case muted
    case enabled
}

public struct PlaylistConfiguration: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var wallpaperIDs: [UUID]
    public var intervalSeconds: TimeInterval
    public var shuffle: Bool
    public var cursor: Int

    public init(
        isEnabled: Bool = false,
        wallpaperIDs: [UUID] = [],
        intervalSeconds: TimeInterval = 900,
        shuffle: Bool = false,
        cursor: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.wallpaperIDs = wallpaperIDs
        self.intervalSeconds = intervalSeconds
        self.shuffle = shuffle
        self.cursor = cursor
    }
}

public enum PlaylistEngine {
    public static func nextID(
        configuration: inout PlaylistConfiguration,
        availableIDs: Set<UUID>,
        randomIndex: ((Int) -> Int)? = nil
    ) -> UUID? {
        let eligible = configuration.wallpaperIDs.filter(availableIDs.contains)
        guard configuration.isEnabled, !eligible.isEmpty else { return nil }

        if configuration.shuffle {
            let pick = randomIndex?(eligible.count) ?? Int.random(in: 0..<eligible.count)
            return eligible[min(max(pick, 0), eligible.count - 1)]
        }

        let index = configuration.cursor % eligible.count
        configuration.cursor = (index + 1) % eligible.count
        return eligible[index]
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var launchAtLogin: Bool
    public var restoreLastConfiguration: Bool
    public var presentationMode: DisplayPresentationMode
    public var defaultScalingMode: WallpaperScalingMode
    public var videoQuality: VideoQuality
    public var maximumFrameRate: Int
    public var batterySaverEnabled: Bool
    public var pauseOnLowPowerMode: Bool
    public var pauseWhileOnBattery: Bool
    public var pauseDuringFullScreenApps: Bool
    public var pauseWhenDisplaySleeps: Bool
    public var resumeAfterWake: Bool
    public var audioBehavior: AudioBehavior
    public var thumbnailCacheLimitBytes: Int64
    public var importBehavior: ImportBehavior
    public var managedLibraryPath: String?
    public var playlist: PlaylistConfiguration
    public var menuBarVisible: Bool
    public var updateChecksEnabled: Bool
    public var diagnosticLoggingEnabled: Bool
    public var synchronizedDuplicatePlayback: Bool

    public init(
        launchAtLogin: Bool = false,
        restoreLastConfiguration: Bool = true,
        presentationMode: DisplayPresentationMode = .perDisplay,
        defaultScalingMode: WallpaperScalingMode = .fill,
        videoQuality: VideoQuality = .balanced,
        maximumFrameRate: Int = 60,
        batterySaverEnabled: Bool = true,
        pauseOnLowPowerMode: Bool = true,
        pauseWhileOnBattery: Bool = false,
        pauseDuringFullScreenApps: Bool = false,
        pauseWhenDisplaySleeps: Bool = true,
        resumeAfterWake: Bool = true,
        audioBehavior: AudioBehavior = .muted,
        thumbnailCacheLimitBytes: Int64 = 1_073_741_824,
        importBehavior: ImportBehavior = .referenceOriginal,
        managedLibraryPath: String? = nil,
        playlist: PlaylistConfiguration = PlaylistConfiguration(),
        menuBarVisible: Bool = true,
        updateChecksEnabled: Bool = false,
        diagnosticLoggingEnabled: Bool = false,
        synchronizedDuplicatePlayback: Bool = true
    ) {
        self.launchAtLogin = launchAtLogin
        self.restoreLastConfiguration = restoreLastConfiguration
        self.presentationMode = presentationMode
        self.defaultScalingMode = defaultScalingMode
        self.videoQuality = videoQuality
        self.maximumFrameRate = maximumFrameRate
        self.batterySaverEnabled = batterySaverEnabled
        self.pauseOnLowPowerMode = pauseOnLowPowerMode
        self.pauseWhileOnBattery = pauseWhileOnBattery
        self.pauseDuringFullScreenApps = pauseDuringFullScreenApps
        self.pauseWhenDisplaySleeps = pauseWhenDisplaySleeps
        self.resumeAfterWake = resumeAfterWake
        self.audioBehavior = audioBehavior
        self.thumbnailCacheLimitBytes = thumbnailCacheLimitBytes
        self.importBehavior = importBehavior
        self.managedLibraryPath = managedLibraryPath
        self.playlist = playlist
        self.menuBarVisible = menuBarVisible
        self.updateChecksEnabled = updateChecksEnabled
        self.diagnosticLoggingEnabled = diagnosticLoggingEnabled
        self.synchronizedDuplicatePlayback = synchronizedDuplicatePlayback
    }
}

public struct PersistedApplicationState: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var wallpapers: [WallpaperMetadata]
    public var assignments: [DisplayAssignment]
    public var settings: AppSettings
    public var sharedWallpaperID: UUID?
    public var lastKnownTopology: DisplayTopology?
    public var playlists: [WallpaperPlaylist]?
    public var activePlaylistID: UUID?
    public var widgets: [DesktopWidget]?
    public var widgetDisplayMode: WidgetDisplayMode?
    public var widgetDisplayConfigurations: [WidgetDisplayConfiguration]?
    public var widgetPerDisplayInitialized: Bool?
    public var defaultWidgetStyle: WidgetVisualStyle?

    public init(
        schemaVersion: Int = 1,
        wallpapers: [WallpaperMetadata] = [],
        assignments: [DisplayAssignment] = [],
        settings: AppSettings = AppSettings(),
        sharedWallpaperID: UUID? = nil,
        lastKnownTopology: DisplayTopology? = nil,
        playlists: [WallpaperPlaylist]? = nil,
        activePlaylistID: UUID? = nil,
        widgets: [DesktopWidget]? = nil,
        widgetDisplayMode: WidgetDisplayMode? = nil,
        widgetDisplayConfigurations: [WidgetDisplayConfiguration]? = nil,
        widgetPerDisplayInitialized: Bool? = nil,
        defaultWidgetStyle: WidgetVisualStyle? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.wallpapers = wallpapers
        self.assignments = assignments
        self.settings = settings
        self.sharedWallpaperID = sharedWallpaperID
        self.lastKnownTopology = lastKnownTopology
        self.playlists = playlists
        self.activePlaylistID = activePlaylistID
        self.widgets = widgets
        self.widgetDisplayMode = widgetDisplayMode
        self.widgetDisplayConfigurations = widgetDisplayConfigurations
        self.widgetPerDisplayInitialized = widgetPerDisplayInitialized
        self.defaultWidgetStyle = defaultWidgetStyle
    }
}
