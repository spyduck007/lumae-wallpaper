import Foundation
import UniformTypeIdentifiers
import AVFoundation
import ImageIO
import CryptoKit
import LumaeCore

actor WallpaperImporter {
    static let allowedTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .gif, .mpeg4Movie, .quickTimeMovie, .video]

    // Reserves a content hash for the duration of processing that file
    // (across the awaits below), so a second concurrent importFiles call
    // on this same actor — e.g. the import panel triggered twice quickly,
    // or overlapping with a drag-and-drop — sees it as already in flight
    // instead of both calls independently passing the duplicate check
    // against the same stale `existing` snapshot.
    private var pendingImportHashes: Set<String> = []

    func importFiles(
        _ urls: [URL],
        behavior: ImportBehavior,
        managedLibraryPath: String?,
        existing: [WallpaperMetadata],
        thumbnailCache: ThumbnailCache
    ) async -> WallpaperImportOutcome {
        var result: [WallpaperMetadata] = []
        var failures: [ImportFailure] = []
        var hashes = Set(existing.map(\.contentHash))

        for source in urls {
            var reservedHash: String?
            var copiedURL: URL?
            do {
                guard let format = SupportedWallpaperFormat.from(pathExtension: source.pathExtension) else {
                    throw ImportError.unsupported(source.lastPathComponent)
                }
                let hash = try hashFile(source)
                guard !hashes.contains(hash), !pendingImportHashes.contains(hash) else {
                    continue
                }
                pendingImportHashes.insert(hash)
                reservedHash = hash

                let effective = try managedURL(for: source, behavior: behavior, explicitPath: managedLibraryPath)
                if behavior == .copyToManagedLibrary { copiedURL = effective }
                let values = try effective.resourceValues(forKeys: [.fileSizeKey])
                let dimensions = try await mediaDimensions(effective, kind: format.kind)
                let thumb = try await thumbnailCache.thumbnail(for: effective, kind: format.kind, hash: hash)

                result.append(WallpaperMetadata(name: source.deletingPathExtension().lastPathComponent, originalFilePath: source.path,
                    managedLibraryPath: behavior == .copyToManagedLibrary ? effective.path : nil, format: format,
                    fileSizeBytes: Int64(values.fileSize ?? 0), pixelWidth: dimensions.width, pixelHeight: dimensions.height,
                    durationSeconds: dimensions.duration, frameRate: dimensions.frameRate, thumbnailPath: thumb.path, contentHash: hash))
                hashes.insert(hash)
            } catch {
                // A file already copied into the managed library before a
                // later step (metadata/thumbnail) failed would otherwise
                // sit on disk forever, referenced by nothing.
                if let copiedURL {
                    try? FileManager.default.removeItem(at: copiedURL)
                }
                failures.append(ImportFailure(fileName: source.lastPathComponent, message: error.localizedDescription))
            }
            if let reservedHash {
                pendingImportHashes.remove(reservedHash)
            }
        }
        return WallpaperImportOutcome(imported: result, failures: failures)
    }


    func relink(
        _ wallpaper: WallpaperMetadata,
        to source: URL,
        existing: [WallpaperMetadata],
        thumbnailCache: ThumbnailCache
    ) async throws -> WallpaperMetadata {
        guard let format = SupportedWallpaperFormat.from(pathExtension: source.pathExtension) else {
            throw ImportError.unsupported(source.lastPathComponent)
        }

        let hash = try hashFile(source)
        if existing.contains(where: { $0.id != wallpaper.id && $0.contentHash == hash }) {
            throw ImportError.duplicate(source.lastPathComponent)
        }

        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        let dimensions = try await mediaDimensions(source, kind: format.kind)
        let thumbnail = try await thumbnailCache.thumbnail(
            for: source,
            kind: format.kind,
            hash: hash
        )

        var updated = wallpaper
        updated.originalFilePath = source.path
        updated.managedLibraryPath = nil
        updated.format = format
        updated.fileSizeBytes = Int64(values.fileSize ?? 0)
        updated.pixelWidth = dimensions.width
        updated.pixelHeight = dimensions.height
        updated.durationSeconds = dimensions.duration
        updated.frameRate = dimensions.frameRate
        updated.thumbnailPath = thumbnail.path
        updated.isMissing = false
        updated.contentHash = hash
        return updated
    }

    private func managedURL(for source: URL, behavior: ImportBehavior, explicitPath: String?) throws -> URL {
        guard behavior == .copyToManagedLibrary else { return source }
        let root = explicitPath.map(URL.init(fileURLWithPath:)) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Lumae/Library", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var target = root.appendingPathComponent(source.lastPathComponent); var suffix = 2
        while FileManager.default.fileExists(atPath: target.path) { target = root.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(suffix).\(source.pathExtension)"); suffix += 1 }
        try FileManager.default.copyItem(at: source, to: target); return target
    }

    private func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = SHA256(); while autoreleasepool(invoking: { let data = handle.readData(ofLength: 1024 * 1024); if !data.isEmpty { hasher.update(data: data) }; return !data.isEmpty }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func mediaDimensions(_ url: URL, kind: WallpaperKind) async throws -> (width: Int, height: Int, duration: Double?, frameRate: Double?) {
        if kind == .video {
            let asset = AVURLAsset(url: url); let tracks = try await asset.loadTracks(withMediaType: .video); guard let track = tracks.first else { throw ImportError.unreadable(url.lastPathComponent) }
            let size = try await track.load(.naturalSize).applying(try await track.load(.preferredTransform)); let duration = try await asset.load(.duration)
            return (Int(abs(size.width)), Int(abs(size.height)), CMTimeGetSeconds(duration), Double(try await track.load(.nominalFrameRate)))
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any], let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { throw ImportError.unreadable(url.lastPathComponent) }
        return (w, h, nil, nil)
    }
}

struct WallpaperImportOutcome: Sendable {
    var imported: [WallpaperMetadata]
    var failures: [ImportFailure]
}

struct ImportFailure: Sendable {
    var fileName: String
    var message: String
}

enum ImportError: LocalizedError {
    case unsupported(String), unreadable(String), duplicate(String)
    var errorDescription: String? {
        switch self {
        case .unsupported(let name):
            return "\(name) uses an unsupported format."
        case .unreadable(let name):
            return "Lumae could not read media metadata from \(name)."
        case .duplicate(let name):
            return "\(name) is already in your Lumae library."
        }
    }
}
