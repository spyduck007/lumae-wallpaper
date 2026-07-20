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

        let index = ((configuration.cursor % eligible.count) + eligible.count) % eligible.count
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
    /// The only network access in Lumae besides Sparkle update checks. Off
    /// by default; the weather widget stays in a disabled/glanceable state
    /// until the user explicitly turns this on in Settings.
    public var weatherEnabled: Bool
    public var weatherLocationMode: WeatherLocationMode
    public var weatherManualLocationName: String

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
        synchronizedDuplicatePlayback: Bool = true,
        weatherEnabled: Bool = false,
        weatherLocationMode: WeatherLocationMode = .automatic,
        weatherManualLocationName: String = ""
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
        self.weatherEnabled = weatherEnabled
        self.weatherLocationMode = weatherLocationMode
        self.weatherManualLocationName = weatherManualLocationName
    }

    // AppSettings previously relied on synthesized Codable, which requires
    // every key to be present. A custom decoder with decodeIfPresent
    // defaults for every field (not just the new weather ones) keeps
    // existing users' state.json readable after this update instead of
    // failing to decode outright.
    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case restoreLastConfiguration
        case presentationMode
        case defaultScalingMode
        case videoQuality
        case maximumFrameRate
        case batterySaverEnabled
        case pauseOnLowPowerMode
        case pauseWhileOnBattery
        case pauseDuringFullScreenApps
        case pauseWhenDisplaySleeps
        case resumeAfterWake
        case audioBehavior
        case thumbnailCacheLimitBytes
        case importBehavior
        case managedLibraryPath
        case playlist
        case menuBarVisible
        case updateChecksEnabled
        case diagnosticLoggingEnabled
        case synchronizedDuplicatePlayback
        case weatherEnabled
        case weatherLocationMode
        case weatherManualLocationName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        restoreLastConfiguration = try container.decodeIfPresent(Bool.self, forKey: .restoreLastConfiguration) ?? true
        presentationMode = try container.decodeIfPresent(DisplayPresentationMode.self, forKey: .presentationMode) ?? .perDisplay
        defaultScalingMode = try container.decodeIfPresent(WallpaperScalingMode.self, forKey: .defaultScalingMode) ?? .fill
        videoQuality = try container.decodeIfPresent(VideoQuality.self, forKey: .videoQuality) ?? .balanced
        maximumFrameRate = try container.decodeIfPresent(Int.self, forKey: .maximumFrameRate) ?? 60
        batterySaverEnabled = try container.decodeIfPresent(Bool.self, forKey: .batterySaverEnabled) ?? true
        pauseOnLowPowerMode = try container.decodeIfPresent(Bool.self, forKey: .pauseOnLowPowerMode) ?? true
        pauseWhileOnBattery = try container.decodeIfPresent(Bool.self, forKey: .pauseWhileOnBattery) ?? false
        pauseDuringFullScreenApps = try container.decodeIfPresent(Bool.self, forKey: .pauseDuringFullScreenApps) ?? false
        pauseWhenDisplaySleeps = try container.decodeIfPresent(Bool.self, forKey: .pauseWhenDisplaySleeps) ?? true
        resumeAfterWake = try container.decodeIfPresent(Bool.self, forKey: .resumeAfterWake) ?? true
        audioBehavior = try container.decodeIfPresent(AudioBehavior.self, forKey: .audioBehavior) ?? .muted
        thumbnailCacheLimitBytes = try container.decodeIfPresent(Int64.self, forKey: .thumbnailCacheLimitBytes) ?? 1_073_741_824
        importBehavior = try container.decodeIfPresent(ImportBehavior.self, forKey: .importBehavior) ?? .referenceOriginal
        managedLibraryPath = try container.decodeIfPresent(String.self, forKey: .managedLibraryPath)
        playlist = try container.decodeIfPresent(PlaylistConfiguration.self, forKey: .playlist) ?? PlaylistConfiguration()
        menuBarVisible = try container.decodeIfPresent(Bool.self, forKey: .menuBarVisible) ?? true
        updateChecksEnabled = try container.decodeIfPresent(Bool.self, forKey: .updateChecksEnabled) ?? false
        diagnosticLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .diagnosticLoggingEnabled) ?? false
        synchronizedDuplicatePlayback = try container.decodeIfPresent(Bool.self, forKey: .synchronizedDuplicatePlayback) ?? true
        weatherEnabled = try container.decodeIfPresent(Bool.self, forKey: .weatherEnabled) ?? false
        weatherLocationMode = try container.decodeIfPresent(WeatherLocationMode.self, forKey: .weatherLocationMode) ?? .automatic
        weatherManualLocationName = try container.decodeIfPresent(String.self, forKey: .weatherManualLocationName) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(restoreLastConfiguration, forKey: .restoreLastConfiguration)
        try container.encode(presentationMode, forKey: .presentationMode)
        try container.encode(defaultScalingMode, forKey: .defaultScalingMode)
        try container.encode(videoQuality, forKey: .videoQuality)
        try container.encode(maximumFrameRate, forKey: .maximumFrameRate)
        try container.encode(batterySaverEnabled, forKey: .batterySaverEnabled)
        try container.encode(pauseOnLowPowerMode, forKey: .pauseOnLowPowerMode)
        try container.encode(pauseWhileOnBattery, forKey: .pauseWhileOnBattery)
        try container.encode(pauseDuringFullScreenApps, forKey: .pauseDuringFullScreenApps)
        try container.encode(pauseWhenDisplaySleeps, forKey: .pauseWhenDisplaySleeps)
        try container.encode(resumeAfterWake, forKey: .resumeAfterWake)
        try container.encode(audioBehavior, forKey: .audioBehavior)
        try container.encode(thumbnailCacheLimitBytes, forKey: .thumbnailCacheLimitBytes)
        try container.encode(importBehavior, forKey: .importBehavior)
        try container.encodeIfPresent(managedLibraryPath, forKey: .managedLibraryPath)
        try container.encode(playlist, forKey: .playlist)
        try container.encode(menuBarVisible, forKey: .menuBarVisible)
        try container.encode(updateChecksEnabled, forKey: .updateChecksEnabled)
        try container.encode(diagnosticLoggingEnabled, forKey: .diagnosticLoggingEnabled)
        try container.encode(synchronizedDuplicatePlayback, forKey: .synchronizedDuplicatePlayback)
        try container.encode(weatherEnabled, forKey: .weatherEnabled)
        try container.encode(weatherLocationMode, forKey: .weatherLocationMode)
        try container.encode(weatherManualLocationName, forKey: .weatherManualLocationName)
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
    public var scenes: [DesktopScene]?
    public var activeSceneID: UUID?
    public var defaultSceneID: UUID?

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
        defaultWidgetStyle: WidgetVisualStyle? = nil,
        scenes: [DesktopScene]? = nil,
        activeSceneID: UUID? = nil,
        defaultSceneID: UUID? = nil
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
        self.scenes = scenes
        self.activeSceneID = activeSceneID
        self.defaultSceneID = defaultSceneID
    }
}
