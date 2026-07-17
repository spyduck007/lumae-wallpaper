import AppKit
import AVFoundation
import LumaeCore

@MainActor
final class WallpaperEngine {
    private let windows: WallpaperWindowManager
    private let fullScreenController: FullScreenPerformanceController
    private let imageCache = NSCache<NSString, NSImage>()
    private var videoSessions: [VideoPlaybackKey: VideoPlaybackSession] = [:]
    private var currentState: PersistedApplicationState?
    private var coveredDisplayIDs: Set<String> = []
    private var isManuallyPaused = false
    private var playbackRetirementTasks: [Task<Void, Never>] = []

    init() {
        let windows = WallpaperWindowManager()
        let fullScreenController = FullScreenPerformanceController()
        self.windows = windows
        self.fullScreenController = fullScreenController
        imageCache.countLimit = 8

        windows.onSystemRevealGesture = { [weak fullScreenController] in
            fullScreenController?.revealDesktopForSystemTransition()
        }
        fullScreenController.onCoveredDisplayIDsChange = { [weak self] displayIDs in
            self?.applyCoveredDisplayIDs(displayIDs)
        }
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
        guard !topology.displays.isEmpty else {
            currentState = state
            stopAllPlayback()
            windows.removeAll()
            fullScreenController.update(enabled: false, topology: topology)
            return
        }

        let previousState = currentState
        let previousSessions = videoSessions
        currentState = state
        videoSessions = [:]
        windows.beginReplacement()

        do {
            switch state.settings.presentationMode {
            case .perDisplay:
                try applyPerDisplay(state: state, topology: topology)
            case .duplicate:
                try applyShared(state: state, topology: topology, span: false)
            case .span:
                try applyShared(state: state, topology: topology, span: true)
            }

            coveredDisplayIDs.formIntersection(topology.activeDisplayIDs)
            windows.setPerformanceSuspended(coveredDisplayIDs)
            fullScreenController.update(
                enabled: state.settings.pauseDuringFullScreenApps,
                topology: topology
            )
            applyPlaybackPolicy()
            windows.commitReplacement()
            retirePlaybackSessions(previousSessions)
        } catch {
            stopPlaybackSessions(videoSessions)
            videoSessions = previousSessions
            currentState = previousState
            windows.rollbackReplacement()
            applyPlaybackPolicy()
            throw error
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
        isManuallyPaused = true
        applyPlaybackPolicy()
    }

    func resume() {
        isManuallyPaused = false
        applyPlaybackPolicy()
    }

    func updateFullScreenSuspension(
        enabled: Bool,
        topology: DisplayTopology
    ) {
        fullScreenController.update(enabled: enabled, topology: topology)
        if !enabled {
            applyCoveredDisplayIDs([])
        }
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
                videoQuality: state.settings.videoQuality,
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
            let playbackURL = optimizedPlaybackURL(
                for: wallpaper,
                quality: state.settings.videoQuality,
                maximumFrameRate: state.settings.maximumFrameRate,
                displayPixelSizes: topology.displays.map(\.pixelSize)
            )
            let session = try videoSession(
                path: playbackURL.path,
                muted: state.settings.audioBehavior == .muted,
                maxFrameRate: state.settings.maximumFrameRate,
                displayIDs: topology.activeDisplayIDs
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

        case .unsupported:
            throw EngineError.unsupported
        }
    }

    private func show(
        wallpaper: WallpaperMetadata,
        on display: DisplayDescriptor,
        scalingMode: WallpaperScalingMode,
        maxFrameRate: Int,
        videoQuality: VideoQuality,
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
            let playbackURL = optimizedPlaybackURL(
                for: wallpaper,
                quality: videoQuality,
                maximumFrameRate: maxFrameRate,
                displayPixelSizes: [display.pixelSize]
            )
            let session = try videoSession(
                path: playbackURL.path,
                muted: audioBehavior == .muted,
                maxFrameRate: maxFrameRate,
                displayIDs: [display.id]
            )
            windows.showVideo(
                player: session.player,
                display: display,
                sourceSize: sourceSize,
                mode: scalingMode,
                widgets: widgets
            )

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

    private func optimizedPlaybackURL(
        for wallpaper: WallpaperMetadata,
        quality: VideoQuality,
        maximumFrameRate: Int,
        displayPixelSizes: [LSize]
    ) -> URL {
        guard let profile = VideoOptimizationPlanner.profile(
            for: wallpaper,
            quality: quality,
            maximumFrameRate: maximumFrameRate,
            displayPixelSizes: displayPixelSizes
        ), let optimized = VideoOptimizationService.existingURL(
            for: wallpaper,
            profile: profile
        ) else {
            return URL(fileURLWithPath: wallpaper.effectiveFilePath)
        }
        return optimized
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
        maxFrameRate: Int,
        displayIDs: Set<String>
    ) throws -> VideoPlaybackSession {
        let key = VideoPlaybackKey(path: path, muted: muted)
        if let existing = videoSessions[key] {
            existing.displayIDs.formUnion(displayIDs)
            return existing
        }
        let service = SharedVideoPlaybackService()
        let player = try service.prepare(
            url: URL(fileURLWithPath: path),
            muted: muted,
            maxFrameRate: maxFrameRate
        )
        let session = VideoPlaybackSession(
            service: service,
            player: player,
            displayIDs: displayIDs
        )
        videoSessions[key] = session
        return session
    }

    private func applyCoveredDisplayIDs(_ displayIDs: Set<String>) {
        coveredDisplayIDs = displayIDs
        windows.setPerformanceSuspended(displayIDs)
        applyPlaybackPolicy()
    }

    private func applyPlaybackPolicy() {
        for session in videoSessions.values {
            if PlaybackSuspensionPolicy.shouldPause(
                sessionDisplayIDs: session.displayIDs,
                coveredDisplayIDs: coveredDisplayIDs,
                manuallyPaused: isManuallyPaused
            ) {
                session.service.pause()
            } else {
                session.service.resume()
            }
        }
    }

    private func retirePlaybackSessions(
        _ sessions: [VideoPlaybackKey: VideoPlaybackSession]
    ) {
        guard !sessions.isEmpty else { return }
        let task = Task { [sessions] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.stopPlaybackSessions(sessions)
            }
        }
        playbackRetirementTasks.append(task)
        if playbackRetirementTasks.count > 8 {
            playbackRetirementTasks.removeFirst(
                playbackRetirementTasks.count - 8
            )
        }
    }

    private func stopPlaybackSessions(
        _ sessions: [VideoPlaybackKey: VideoPlaybackSession]
    ) {
        sessions.values.forEach { $0.service.stop() }
    }

    private func stopAllPlayback() {
        playbackRetirementTasks.forEach { $0.cancel() }
        playbackRetirementTasks.removeAll()
        stopPlaybackSessions(videoSessions)
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
    var displayIDs: Set<String>

    init(
        service: SharedVideoPlaybackService,
        player: AVQueuePlayer,
        displayIDs: Set<String>
    ) {
        self.service = service
        self.player = player
        self.displayIDs = displayIDs
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
