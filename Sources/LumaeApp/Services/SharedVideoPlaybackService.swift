import AVFoundation
import AppKit

@MainActor
final class SharedVideoPlaybackService {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observers: [NSObjectProtocol] = []
    private var shouldResumeAfterWake = false

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleep() })
        observers.append(nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.wake() })
        observers.append(nc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.sleep() })
        observers.append(nc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.wake() })
    }

    deinit { observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver) }

    func prepare(url: URL, muted: Bool, maxFrameRate: Int) throws -> AVQueuePlayer {
        stop()
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1
        let queue = AVQueuePlayer()
        queue.isMuted = muted
        queue.actionAtItemEnd = .advance
        queue.automaticallyWaitsToMinimizeStalling = false
        queue.preventsDisplaySleepDuringVideoPlayback = false
        let looper = AVPlayerLooper(player: queue, templateItem: item)
        self.player = queue; self.looper = looper
        return queue
    }
    func play() { player?.play() }
    func pause() { player?.pause() }
    func resume() { player?.play() }
    func stop() { player?.pause(); looper?.disableLooping(); looper = nil; player?.removeAllItems(); player = nil }
    private func sleep() { shouldResumeAfterWake = player?.rate ?? 0 > 0; player?.pause() }
    private func wake() { if shouldResumeAfterWake { player?.play() }; shouldResumeAfterWake = false }
}
