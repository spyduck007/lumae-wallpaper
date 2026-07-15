import AppKit
import Combine
import Darwin
import Foundation

struct NowPlayingSnapshot {
    var title: String
    var artist: String
    var album: String
    var artwork: NSImage?
    var elapsedTime: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
    var updatedAt: Date

    static let empty = NowPlayingSnapshot(
        title: "",
        artist: "",
        album: "",
        artwork: nil,
        elapsedTime: 0,
        duration: 0,
        isPlaying: false,
        updatedAt: Date()
    )

    var hasTrack: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func elapsed(at date: Date) -> TimeInterval {
        guard isPlaying else {
            return min(max(elapsedTime, 0), max(duration, 0))
        }
        let advanced = elapsedTime + date.timeIntervalSince(updatedAt)
        guard duration > 0 else { return max(advanced, 0) }
        return min(max(advanced, 0), duration)
    }
}

final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    @Published private(set) var snapshot = NowPlayingSnapshot.empty

    private typealias InfoCallback = @convention(block) (CFDictionary?) -> Void
    private typealias GetInfoFunction = @convention(c) (
        DispatchQueue,
        InfoCallback
    ) -> Void

    private enum Key {
        case title
        case artist
        case album
        case duration
        case elapsedTime
        case playbackRate
        case artworkData
    }

    private var timer: Timer?
    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var getNowPlayingInfo: GetInfoFunction?
    private var mediaRemoteKeys: [Key: String] = [:]
    private var artworkURL: URL?
    private var artworkDownloadTask: URLSessionDataTask?

    private init() {
        loadMediaRemote()
        refresh()
        timer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
        artworkDownloadTask?.cancel()
        if let mediaRemoteHandle {
            dlclose(mediaRemoteHandle)
        }
    }

    func refresh() {
        guard let getNowPlayingInfo else {
            refreshFromSpotify()
            return
        }

        let callback: InfoCallback = { [weak self] dictionary in
            guard let self else { return }
            DispatchQueue.main.async {
                if !self.consumeMediaRemote(dictionary) {
                    self.refreshFromSpotify()
                }
            }
        }
        getNowPlayingInfo(.main, callback)
    }

    private func loadMediaRemote() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return }
        guard let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            dlclose(handle)
            return
        }

        mediaRemoteHandle = handle
        getNowPlayingInfo = unsafeBitCast(symbol, to: GetInfoFunction.self)
        mediaRemoteKeys = [
            .title: exportedString("kMRMediaRemoteNowPlayingInfoTitle", handle: handle),
            .artist: exportedString("kMRMediaRemoteNowPlayingInfoArtist", handle: handle),
            .album: exportedString("kMRMediaRemoteNowPlayingInfoAlbum", handle: handle),
            .duration: exportedString("kMRMediaRemoteNowPlayingInfoDuration", handle: handle),
            .elapsedTime: exportedString("kMRMediaRemoteNowPlayingInfoElapsedTime", handle: handle),
            .playbackRate: exportedString("kMRMediaRemoteNowPlayingInfoPlaybackRate", handle: handle),
            .artworkData: exportedString("kMRMediaRemoteNowPlayingInfoArtworkData", handle: handle)
        ].compactMapValues { $0 }
    }

    private func exportedString(
        _ symbolName: String,
        handle: UnsafeMutableRawPointer
    ) -> String? {
        guard let symbol = dlsym(handle, symbolName) else { return nil }
        let pointer = symbol.assumingMemoryBound(to: Optional<CFString>.self)
        guard let value = pointer.pointee else { return nil }
        return value as String
    }

    @discardableResult
    private func consumeMediaRemote(_ dictionary: CFDictionary?) -> Bool {
        guard let dictionary else { return false }
        let info = dictionary as NSDictionary
        let title = stringValue(info, key: .title, aliases: ["title"])
        guard !title.isEmpty else { return false }

        artworkDownloadTask?.cancel()
        artworkURL = nil
        snapshot = NowPlayingSnapshot(
            title: title,
            artist: stringValue(info, key: .artist, aliases: ["artist"]),
            album: stringValue(info, key: .album, aliases: ["album"]),
            artwork: imageValue(info, key: .artworkData, aliases: ["artworkData"]),
            elapsedTime: numberValue(
                info,
                key: .elapsedTime,
                aliases: ["elapsedTime"]
            ),
            duration: numberValue(info, key: .duration, aliases: ["duration"]),
            isPlaying: numberValue(
                info,
                key: .playbackRate,
                aliases: ["playbackRate"]
            ) > 0,
            updatedAt: Date()
        )
        return true
    }

    private func refreshFromSpotify() {
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.spotify.client"
        ).isEmpty == false else {
            snapshot = .empty
            return
        }

        let source = #"""
        tell application "Spotify"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) as string) & linefeed & ((player position) as string) & linefeed & ((player state) as string) & linefeed & (artwork url of t)
        end tell
        """#

        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error),
              error == nil else {
            snapshot = .empty
            return
        }

        let lines = result.stringValue?.components(separatedBy: .newlines) ?? []
        guard lines.count >= 6, !lines[0].isEmpty else {
            snapshot = .empty
            return
        }

        let durationMilliseconds = Double(lines[safe: 3] ?? "") ?? 0
        let positionSeconds = Double(lines[safe: 4] ?? "") ?? 0
        let state = lines[safe: 5] ?? ""
        let artworkString = lines[safe: 6] ?? ""
        let newArtworkURL = URL(string: artworkString)

        snapshot = NowPlayingSnapshot(
            title: lines[0],
            artist: lines[safe: 1] ?? "",
            album: lines[safe: 2] ?? "",
            artwork: newArtworkURL == artworkURL ? snapshot.artwork : nil,
            elapsedTime: positionSeconds,
            duration: durationMilliseconds / 1_000,
            isPlaying: state.caseInsensitiveCompare("playing") == .orderedSame,
            updatedAt: Date()
        )

        if let newArtworkURL, newArtworkURL != artworkURL {
            artworkURL = newArtworkURL
            loadArtwork(from: newArtworkURL)
        }
    }

    private func loadArtwork(from url: URL) {
        artworkDownloadTask?.cancel()
        artworkDownloadTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard self?.artworkURL == url else { return }
                self?.snapshot.artwork = image
            }
        }
        artworkDownloadTask?.resume()
    }

    private func stringValue(
        _ dictionary: NSDictionary,
        key: Key,
        aliases: [String]
    ) -> String {
        for candidate in keyCandidates(key, aliases: aliases) {
            if let value = dictionary[candidate] as? String {
                return value
            }
        }
        return ""
    }

    private func numberValue(
        _ dictionary: NSDictionary,
        key: Key,
        aliases: [String]
    ) -> Double {
        for candidate in keyCandidates(key, aliases: aliases) {
            if let value = dictionary[candidate] as? NSNumber {
                return value.doubleValue
            }
            if let value = dictionary[candidate] as? Double {
                return value
            }
        }
        return 0
    }

    private func imageValue(
        _ dictionary: NSDictionary,
        key: Key,
        aliases: [String]
    ) -> NSImage? {
        for candidate in keyCandidates(key, aliases: aliases) {
            if let data = dictionary[candidate] as? Data,
               let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    private func keyCandidates(_ key: Key, aliases: [String]) -> [String] {
        var values = aliases
        if let exported = mediaRemoteKeys[key] {
            values.insert(exported, at: 0)
        }
        return values
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
