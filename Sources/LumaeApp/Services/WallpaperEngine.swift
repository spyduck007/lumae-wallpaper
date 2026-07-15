import AppKit
import AVFoundation
import LumaeCore

@MainActor
final class WallpaperEngine {
    private let windows = WallpaperWindowManager()
    private let imageCache = NSCache<NSString, NSImage>()
    private var videoSessions: [VideoPlaybackKey: VideoPlaybackSession] = [:]
    private var currentState: PersistedApplicationState?

    init() {
        imageCache.countLimit = 8
    }

    func apply(
        wallpaper: WallpaperMetadata,
        state: PersistedApplicationState,
        topology: DisplayTopology
    ) async throws {
        try await applyConfiguration(state: state, topology: topology)
    }

    func applyConfiguration(
        state: PersistedApplicationState,
        topology: DisplayTopology
    ) async throws {
        currentState = state
        stopAllPlayback()
        windows.removeAll()

        guard !topology.displays.isEmpty else { return }

        switch state.settings.presentationMode {
        case .perDisplay:
            try applyPerDisplay(state: state, topology: topology)
        case .duplicate:
            try applyShared(state: state, topology: topology, span: false)
        case .span:
            try applyShared(state: state, topology: topology, span: true)
        }
    }

    func restore(
        state: PersistedApplicationState,
        topology: DisplayTopology
    ) async {
        try? await applyConfiguration(state: state, topology: topology)
    }

    func topologyDidChange(
        _ topology: DisplayTopology,
        state: PersistedApplicationState
    ) async {
        try? await applyConfiguration(state: state, topology: topology)
    }

    func updateWidgets(
        state: PersistedApplicationState,
        topology: DisplayTopology
    ) {
        currentState = state
        var widgetsByDisplayID: [String: [DesktopWidget]] = [:]
        for display in topology.displays {
            widgetsByDisplayID[display.id] = resolvedWidgets(
                for: display,
                state: state,
                topology: topology
            )
        }
        windows.updateWidgets(widgetsByDisplayID)
    }

    func pause() {
        videoSessions.values.forEach { $0.service.pause() }
    }

    func resume() {
        videoSessions.values.forEach { $0.service.resume() }
    }

    private func applyPerDisplay(
        state: PersistedApplicationState,
        topology: DisplayTopology
    ) throws {
        let restored = DisplayAssignmentRestorer.restore(
            saved: state.assignments,
            onto: topology
        )

        for display in topology.displays {
            guard let assignment = restored[display.id], assignment.enabled,
                  let wallpaperID = assignment.wallpaperID,
                  let wallpaper = state.wallpapers.first(where: { $0.id == wallpaperID }),
                  !wallpaper.isMissing else {
                continue
            }

            try show(
                wallpaper: wallpaper,
                on: display,
                scalingMode: assignment.scalingMode,
                maxFrameRate: assignment.maxFrameRate
                    ?? state.settings.maximumFrameRate,
                audioBehavior: state.settings.audioBehavior,
                widgets: resolvedWidgets(
                    for: display,
                    state: state,
                    topology: topology
                )
            )
        }
    }

    private func applyShared(
        state: PersistedApplicationState,
        topology: DisplayTopology,
        span: Bool
    ) throws {
        guard let wallpaperID = state.sharedWallpaperID,
              let wallpaper = state.wallpapers.first(where: { $0.id == wallpaperID }),
              !wallpaper.isMissing else {
            return
        }

        let sourceSize = LSize(
            width: Double(wallpaper.pixelWidth),
            height: Double(wallpaper.pixelHeight)
        )
        let layout = span
            ? try SpanLayoutEngine.makeLayout(
                topology: topology,
                sourceSize: sourceSize,
                mode: state.settings.defaultScalingMode
            )
            : nil

        switch wallpaper.kind {
        case .image, .animatedImage:
            let image = try cachedImage(at: wallpaper.effectiveFilePath)

            for display in topology.displays {
                let slice = layout?.slices.first { $0.displayID == display.id }
                windows.showStatic(
                    image: image,
                    display: display,
                    sourceSize: sourceSize,
                    mode: span ? .stretch : state.settings.defaultScalingMode,
                    spanSlice: slice,
                    widgets: resolvedWidgets(
                        for: display,
                        state: state,
                        topology: topology
                    )
                )
            }

        case .video:
            let session = try videoSession(
                path: wallpaper.effectiveFilePath,
                muted: state.settings.audioBehavior == .muted,
                maxFrameRate: state.settings.maximumFrameRate
            )

            for display in topology.displays {
                let slice = layout?.slices.first { $0.displayID == display.id }
                windows.showVideo(
                    player: session.player,
                    display: display,
                    sourceSize: sourceSize,
                    mode: span ? .stretch : state.settings.defaultScalingMode,
                    spanSlice: slice,
                    widgets: resolvedWidgets(
                        for: display,
                        state: state,
                        topology: topology
                    )
                )
            }
            session.service.play()

        case .unsupported:
            throw EngineError.unsupported
        }
    }

    private func show(
        wallpaper: WallpaperMetadata,
        on display: DisplayDescriptor,
        scalingMode: WallpaperScalingMode,
        maxFrameRate: Int,
        audioBehavior: AudioBehavior,
        widgets: [DesktopWidget]
    ) throws {
        let sourceSize = LSize(
            width: Double(wallpaper.pixelWidth),
            height: Double(wallpaper.pixelHeight)
        )

        switch wallpaper.kind {
        case .image, .animatedImage:
            let image = try cachedImage(at: wallpaper.effectiveFilePath)
            windows.showStatic(
                image: image,
                display: display,
                sourceSize: sourceSize,
                mode: scalingMode,
                widgets: widgets
            )

        case .video:
            let session = try videoSession(
                path: wallpaper.effectiveFilePath,
                muted: audioBehavior == .muted,
                maxFrameRate: maxFrameRate
            )
            windows.showVideo(
                player: session.player,
                display: display,
                sourceSize: sourceSize,
                mode: scalingMode,
                widgets: widgets
            )
            session.service.play()

        case .unsupported:
            throw EngineError.unsupported
        }
    }

    private func resolvedWidgets(
        for display: DisplayDescriptor,
        state: PersistedApplicationState,
        topology: DisplayTopology
    ) -> [DesktopWidget] {
        WidgetDisplayResolver.widgets(
            for: display,
            mode: state.widgetDisplayMode ?? .mirrored,
            mirroredWidgets: state.widgets ?? [],
            configurations: state.widgetDisplayConfigurations ?? [],
            excludingConfigurationIDs: topology.activeDisplayIDs.subtracting([
                display.id
            ])
        )
    }

    private func cachedImage(at path: String) throws -> NSImage {
        let key = path as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOfFile: path) else {
            throw EngineError.unreadable
        }
        imageCache.setObject(image, forKey: key)
        return image
    }

    private func videoSession(
        path: String,
        muted: Bool,
        maxFrameRate: Int
    ) throws -> VideoPlaybackSession {
        let key = VideoPlaybackKey(path: path, muted: muted)
        if let existing = videoSessions[key] {
            return existing
        }
        let service = SharedVideoPlaybackService()
        let player = try service.prepare(
            url: URL(fileURLWithPath: path),
            muted: muted,
            maxFrameRate: maxFrameRate
        )
        let session = VideoPlaybackSession(service: service, player: player)
        videoSessions[key] = session
        return session
    }

    private func stopAllPlayback() {
        videoSessions.values.forEach { $0.service.stop() }
        videoSessions.removeAll()
    }
}

private struct VideoPlaybackKey: Hashable {
    var path: String
    var muted: Bool
}

@MainActor
private final class VideoPlaybackSession {
    let service: SharedVideoPlaybackService
    let player: AVQueuePlayer

    init(service: SharedVideoPlaybackService, player: AVQueuePlayer) {
        self.service = service
        self.player = player
    }
}

enum EngineError: LocalizedError {
    case missingFile
    case unsupported
    case unreadable

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "The wallpaper file is missing. Locate or reimport it first."
        case .unsupported:
            return "This wallpaper format is not supported."
        case .unreadable:
            return "The wallpaper could not be decoded."
        }
    }
}
