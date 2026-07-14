import AppKit
import AVFoundation
import LumaeCore

actor ThumbnailCache {
    private var root: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Lumae/Thumbnails", isDirectory: true) }
    func thumbnail(for source: URL, kind: WallpaperKind, hash: String) async throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("\(hash).jpg"); if FileManager.default.fileExists(atPath: target.path) { return target }
        let image: NSImage
        if kind == .video {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: source)); gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: 800, height: 500)
            image = NSImage(cgImage: try await gen.image(at: .zero).image, size: .zero)
        } else { guard let loaded = NSImage(contentsOf: source) else { throw ImportError.unreadable(source.lastPathComponent) }; image = loaded }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { throw ImportError.unreadable(source.lastPathComponent) }
        try data.write(to: target, options: .atomic); return target
    }
    func cleanup(limit: Int64) throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentAccessDateKey]
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys))
        let entries = files.compactMap { url -> CacheEntry? in let v = try? url.resourceValues(forKeys: keys); return CacheEntry(path: url.path, sizeBytes: Int64(v?.fileSize ?? 0), lastAccessed: v?.contentAccessDate ?? .distantPast) }
        for entry in CachePolicy.evictionCandidates(entries: entries, limitBytes: limit) { try? FileManager.default.removeItem(atPath: entry.path) }
    }
}
