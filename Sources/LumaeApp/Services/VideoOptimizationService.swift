import AVFoundation
import CoreGraphics
import Foundation
import LumaeCore

struct VideoOptimizationRequest: Hashable, Sendable {
    var wallpaper: WallpaperMetadata
    var profile: VideoOptimizationProfile
}

enum VideoOptimizationState: Equatable {
    case original
    case available(VideoOptimizationProfile, Int64)
    case preparing(VideoOptimizationProfile, Double)
    case failed(String)
}

actor VideoOptimizationService {
    private var activeExports: [String: Task<URL, Error>] = [:]

    // Distinct videos needing optimization (e.g. several displays each
    // assigned a different large video, or a quality/FPS change that
    // invalidates every cached profile at once) used to all transcode
    // concurrently, fighting the currently-playing wallpaper for the same
    // encode/decode hardware. Serializing exports keeps background
    // transcoding from competing with live playback smoothness.
    private let maxConcurrentExports = 1
    private var runningExportCount = 0
    private var exportWaiters: [CheckedContinuation<Void, Never>] = []

    static func optimizedURL(
        contentHash: String,
        profile: VideoOptimizationProfile
    ) -> URL {
        cacheRoot
            .appendingPathComponent(contentHash, isDirectory: true)
            .appendingPathComponent("\(profile.cacheKey).mov")
    }

    static func existingURL(
        for wallpaper: WallpaperMetadata,
        profile: VideoOptimizationProfile
    ) -> URL? {
        let url = optimizedURL(
            contentHash: wallpaper.contentHash,
            profile: profile
        )
        guard FileManager.default.fileExists(atPath: url.path),
              ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
            return nil
        }
        return url
    }

    static func cachedSize(
        for wallpaper: WallpaperMetadata,
        profile: VideoOptimizationProfile
    ) -> Int64? {
        guard let url = existingURL(for: wallpaper, profile: profile) else {
            return nil
        }
        return Int64(
            (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        )
    }

    func optimize(
        request: VideoOptimizationRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        if let existing = Self.existingURL(
            for: request.wallpaper,
            profile: request.profile
        ) {
            return existing
        }

        let key = "\(request.wallpaper.contentHash)-\(request.profile.cacheKey)"
        if let active = activeExports[key] {
            return try await active.value
        }

        let task = Task<URL, Error>(priority: .utility) { [weak self] in
            await self?.acquireExportSlot()
            defer { Task { [weak self] in await self?.releaseExportSlot() } }
            return try await Self.export(request: request, progress: progress)
        }
        activeExports[key] = task
        defer { activeExports[key] = nil }
        return try await task.value
    }

    private func acquireExportSlot() async {
        if runningExportCount < maxConcurrentExports {
            runningExportCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            exportWaiters.append(continuation)
        }
        runningExportCount += 1
    }

    private func releaseExportSlot() {
        runningExportCount -= 1
        guard !exportWaiters.isEmpty else { return }
        exportWaiters.removeFirst().resume()
    }

    func removeOptimizedCopies(for wallpaper: WallpaperMetadata) throws {
        let directory = Self.cacheRoot.appendingPathComponent(
            wallpaper.contentHash,
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static var cacheRoot: URL {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Lumae/OptimizedVideos", isDirectory: true)
    }

    private static func export(
        request: VideoOptimizationRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let sourceURL = URL(fileURLWithPath: request.wallpaper.effectiveFilePath)
        let asset = AVURLAsset(
            url: sourceURL,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw VideoOptimizationError.noVideoTrack
        }

        let targetURL = optimizedURL(
            contentHash: request.wallpaper.contentHash,
            profile: request.profile
        )
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = targetURL
            .deletingPathExtension()
            .appendingPathExtension("partial.mov")
        try? FileManager.default.removeItem(at: temporaryURL)

        let compatiblePresets = AVAssetExportSession.exportPresets(
            compatibleWith: asset
        )
        let preset = compatiblePresets.contains(
            AVAssetExportPresetHEVCHighestQuality
        )
            ? AVAssetExportPresetHEVCHighestQuality
            : AVAssetExportPresetHighestQuality
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: preset
        ) else {
            throw VideoOptimizationError.cannotCreateExporter
        }

        exporter.outputURL = temporaryURL
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = false
        exporter.videoComposition = try await videoComposition(
            asset: asset,
            track: track,
            profile: request.profile
        )

        let progressTask = Task {
            while !Task.isCancelled {
                progress(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { progressTask.cancel() }

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    exporter.exportAsynchronously {
                        switch exporter.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        case .failed:
                            continuation.resume(
                                throwing: exporter.error
                                    ?? VideoOptimizationError.exportFailed
                            )
                        default:
                            continuation.resume(
                                throwing: VideoOptimizationError.exportFailed
                            )
                        }
                    }
                }
            } onCancel: {
                exporter.cancelExport()
            }

            // Replace atomically so a crash or failure mid-swap can never
            // leave the cache with neither the old nor the new copy:
            // replaceItemAt keeps the original in place until the new item
            // has been fully installed.
            _ = try FileManager.default.replaceItemAt(
                targetURL,
                withItemAt: temporaryURL
            )
            progress(1)
            return targetURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func videoComposition(
        asset: AVAsset,
        track: AVAssetTrack,
        profile: VideoOptimizationProfile
    ) async throws -> AVMutableVideoComposition {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformed = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        let sourceSize = transformed.size

        let widthScale = CGFloat(profile.maximumWidth) / max(sourceSize.width, 1)
        let heightScale = CGFloat(profile.maximumHeight) / max(sourceSize.height, 1)
        let scale = min(widthScale, heightScale, 1)
        let renderSize = CGSize(
            width: max((sourceSize.width * scale).rounded(.down), 2),
            height: max((sourceSize.height * scale).rounded(.down), 2)
        )
        let evenRenderSize = CGSize(
            width: CGFloat(Int(renderSize.width) / 2 * 2),
            height: CGFloat(Int(renderSize.height) / 2 * 2)
        )

        var transform = preferredTransform
        transform = transform.concatenating(
            CGAffineTransform(
                translationX: -transformed.minX,
                y: -transformed.minY
            )
        )
        transform = transform.concatenating(
            CGAffineTransform(scaleX: scale, y: scale)
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: track
        )
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: try await asset.load(.duration)
        )
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = evenRenderSize
        composition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(profile.maximumFrameRate)
        )
        return composition
    }
}

enum VideoOptimizationError: LocalizedError {
    case noVideoTrack
    case cannotCreateExporter
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The video does not contain a readable video track."
        case .cannotCreateExporter:
            return "This video cannot be optimized on this Mac."
        case .exportFailed:
            return "The optimized video could not be created."
        }
    }
}
