import AppKit
import AVFoundation
import CoreMedia
import LumaeCore

@MainActor
final class WallpaperEngine {
    private let windows = WallpaperWindowManager()
    private let video = SharedVideoPlaybackService()
    private var currentState: PersistedApplicationState?
    private var currentWallpaper: WallpaperMetadata?

    func apply(wallpaper: WallpaperMetadata, state: PersistedApplicationState, topology: DisplayTopology) async throws {
        currentState = state; currentWallpaper = wallpaper
        video.stop(); windows.removeAll()
        guard !wallpaper.isMissing else { throw EngineError.missingFile }
        switch wallpaper.kind {
        case .video:
            try applyVideo(wallpaper, state: state, topology: topology)
        case .image, .animatedImage:
            try applyStatic(wallpaper, state: state, topology: topology)
        case .unsupported:
            throw EngineError.unsupported
        }
    }

    func restore(state: PersistedApplicationState, topology: DisplayTopology) async {
        guard let id = state.sharedWallpaperID, let item = state.wallpapers.first(where: { $0.id == id }) else { return }
        try? await apply(wallpaper: item, state: state, topology: topology)
    }

    func topologyDidChange(_ topology: DisplayTopology, state: PersistedApplicationState) async {
        guard let wallpaper = currentWallpaper else { return }
        try? await apply(wallpaper: wallpaper, state: state, topology: topology)
    }

    func pause() { video.pause() }
    func resume() { video.resume() }

    private func applyStatic(_ wallpaper: WallpaperMetadata, state: PersistedApplicationState, topology: DisplayTopology) throws {
        guard let image = NSImage(contentsOfFile: wallpaper.effectiveFilePath) else { throw EngineError.unreadable }
        if state.settings.presentationMode == .perDisplay {
            let restored = DisplayAssignmentRestorer.restore(saved: state.assignments, onto: topology)
            for display in topology.displays where restored[display.id]?.enabled != false {
                windows.showStatic(image: image, display: display, sourceSize: LSize(width: Double(wallpaper.pixelWidth), height: Double(wallpaper.pixelHeight)), mode: restored[display.id]?.scalingMode ?? state.settings.defaultScalingMode)
            }
        } else {
            let layout = try SpanLayoutEngine.makeLayout(topology: topology, sourceSize: LSize(width: Double(wallpaper.pixelWidth), height: Double(wallpaper.pixelHeight)), mode: state.settings.defaultScalingMode)
            for display in topology.displays { if let slice = layout.slices.first(where: { $0.displayID == display.id }) { windows.showStatic(image: image, display: display, sourceSize: LSize(width: Double(wallpaper.pixelWidth), height: Double(wallpaper.pixelHeight)), mode: state.settings.presentationMode == .span ? .stretch : state.settings.defaultScalingMode, spanSlice: state.settings.presentationMode == .span ? slice : nil) } }
        }
    }

    private func applyVideo(_ wallpaper: WallpaperMetadata, state: PersistedApplicationState, topology: DisplayTopology) throws {
        let url = URL(fileURLWithPath: wallpaper.effectiveFilePath)
        let player = try video.prepare(url: url, muted: state.settings.audioBehavior == .muted, maxFrameRate: state.settings.maximumFrameRate)
        let source = LSize(width: Double(wallpaper.pixelWidth), height: Double(wallpaper.pixelHeight))
        let layout = state.settings.presentationMode == .span ? try SpanLayoutEngine.makeLayout(topology: topology, sourceSize: source, mode: state.settings.defaultScalingMode) : nil
        for display in topology.displays {
            let slice = layout?.slices.first(where: { $0.displayID == display.id })
            windows.showVideo(player: player, display: display, sourceSize: source, mode: state.settings.defaultScalingMode, spanSlice: slice)
        }
        video.play()
    }
}

enum EngineError: LocalizedError { case missingFile, unsupported, unreadable
    var errorDescription: String? { switch self { case .missingFile: return "The wallpaper file is missing. Locate or reimport it first."; case .unsupported: return "This wallpaper format is not supported."; case .unreadable: return "The wallpaper could not be decoded." } }
}
