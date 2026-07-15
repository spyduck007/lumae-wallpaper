import AppKit
import AVFoundation
import LumaeCore

@MainActor
final class WallpaperEngine {
    private let windows = WallpaperWindowManager()
    private let sharedVideo = SharedVideoPlaybackService()
    private var displayVideos: [String: SharedVideoPlaybackService] = [:]
    private var currentState: PersistedApplicationState?

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
        sharedVideo.pause()
        displayVideos.values.forEach { $0.pause() }
    }

    func resume() {
        sharedVideo.resume()
        displayVideos.values.forEach { $0.resume() }
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
            guard let image = NSImage(contentsOfFile: wallpaper.effectiveFilePath) else {
                throw EngineError.unreadable
            }

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
            let player = try sharedVideo.prepare(
                url: URL(fileURLWithPath: wallpaper.effectiveFilePath),
                muted: state.settings.audioBehavior == .muted,
                maxFrameRate: state.settings.maximumFrameRate
            )

            for display in topology.displays {
                let slice = layout?.slices.first { $0.displayID == display.id }
                windows.showVideo(
                    player: player,
                    display: display,
                    sourceSize: sourceSize,
                    mode: span ? .stretch : state.settings.defaultScalingMode,
                    spanSlice: slice,
                    maxFrameRate: state.settings.maximumFrameRate,
                    widgets: resolvedWidgets(
                        for: display,
                        state: state,
                        topology: topology
                    )
                )
            }
            sharedVideo.play()

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
            guard let image = NSImage(contentsOfFile: wallpaper.effectiveFilePath) else {
                throw EngineError.unreadable
            }
            windows.showStatic(
                image: image,
                display: display,
                sourceSize: sourceSize,
                mode: scalingMode,
                widgets: widgets
            )

        case .video:
            let playback = SharedVideoPlaybackService()
            let player = try playback.prepare(
                url: URL(fileURLWithPath: wallpaper.effectiveFilePath),
                muted: audioBehavior == .muted,
                maxFrameRate: maxFrameRate
            )
            windows.showVideo(
                player: player,
                display: display,
                sourceSize: sourceSize,
                mode: scalingMode,
                maxFrameRate: maxFrameRate,
                widgets: widgets
            )
            displayVideos[display.id] = playback
            playback.play()

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

    private func stopAllPlayback() {
        sharedVideo.stop()
        displayVideos.values.forEach { $0.stop() }
        displayVideos.removeAll()
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
