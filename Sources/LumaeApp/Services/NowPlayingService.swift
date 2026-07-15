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
        guard isPlaying else { return min(max(elapsedTime, 0), max(duration, 0)) }
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

    private var timer: Timer?
    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var getNowPlayingInfo: GetInfoFunction?

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
        if let mediaRemoteHandle {
            dlclose(mediaRemoteHandle)
        }
    }

    func refresh() {
        guard let getNowPlayingInfo else {
            snapshot = .empty
            return
        }

        let callback: InfoCallback = { [weak self] dictionary in
            guard let self else { return }
            DispatchQueue.main.async {
                self.consume(dictionary)
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
    }

    private func consume(_ dictionary: CFDictionary?) {
        guard let dictionary else {
            snapshot = .empty
            return
        }

        let info = dictionary as NSDictionary
        let title = stringValue(
            info,
            keys: [
                "kMRMediaRemoteNowPlayingInfoTitle",
                "title"
            ]
        )

        guard !title.isEmpty else {
            snapshot = .empty
            return
        }

        let artist = stringValue(
            info,
            keys: [
                "kMRMediaRemoteNowPlayingInfoArtist",
                "artist"
            ]
        )
        let album = stringValue(
            info,
            keys: [
                "kMRMediaRemoteNowPlayingInfoAlbum",
                "album"
            ]
        )
        let duration = numberValue(
            info,
            keys: [
                "kMRMediaRemoteNowPlayingInfoDuration",
                "duration"
            ]
        )
        let elapsed = numberValue(
            info,
            keys: [
                "kMRMediaRemoteNowPlayingInfoElapsedTime",
                "elapsedTime"
            ]
        )
        let playbackRate = numberValue(
            info,
            keys: [
                "kMRMediaRemoteNowPlayingInfoPlaybackRate",
                "playbackRate"
            ]
        )
        let artwork = imageValue(
            info,
            keys: [
                "kMRMediaRemoteNowPlayingInfoArtworkData",
                "artworkData"
            ]
        )

        snapshot = NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            elapsedTime: elapsed,
            duration: duration,
            isPlaying: playbackRate > 0,
            updatedAt: Date()
        )
    }

    private func stringValue(
        _ dictionary: NSDictionary,
        keys: [String]
    ) -> String {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }
        return ""
    }

    private func numberValue(
        _ dictionary: NSDictionary,
        keys: [String]
    ) -> Double {
        for key in keys {
            if let value = dictionary[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = dictionary[key] as? Double {
                return value
            }
        }
        return 0
    }

    private func imageValue(
        _ dictionary: NSDictionary,
        keys: [String]
    ) -> NSImage? {
        for key in keys {
            if let data = dictionary[key] as? Data,
               let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }
}
