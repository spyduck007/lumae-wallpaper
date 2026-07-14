import AppKit
import AVFoundation
import LumaeCore

@MainActor
final class WallpaperWindowManager {
    private var windows: [String: WallpaperWindow] = [:]

    func removeAll() { windows.values.forEach { $0.orderOut(nil); $0.contentView = nil }; windows.removeAll() }

    func showStatic(image: NSImage, display: DisplayDescriptor, sourceSize: LSize, mode: WallpaperScalingMode, spanSlice: SpanSlice? = nil) {
        let view = StaticWallpaperView(image: image, sourceSize: sourceSize, mode: mode, spanSlice: spanSlice)
        install(view: view, display: display)
    }

    func showVideo(player: AVPlayer, display: DisplayDescriptor, sourceSize: LSize, mode: WallpaperScalingMode, spanSlice: SpanSlice? = nil) {
        let view = VideoWallpaperView(player: player, sourceSize: sourceSize, mode: mode, spanSlice: spanSlice)
        install(view: view, display: display)
    }

    private func install(view: NSView, display: DisplayDescriptor) {
        let frame = NSRect(x: display.framePoints.minX, y: display.framePoints.minY, width: display.framePoints.size.width, height: display.framePoints.size.height)
        let window = WallpaperWindow(contentRect: frame)
        window.contentView = view; window.setFrame(frame, display: true); window.orderBack(nil)
        windows[display.id] = window
    }
}

final class WallpaperWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = true; hasShadow = false; ignoresMouseEvents = true; backgroundColor = .black
        hidesOnDeactivate = false; isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class StaticWallpaperView: NSView {
    private let imageLayer = CALayer(); private let sourceSize: LSize; private let mode: WallpaperScalingMode; private let slice: SpanSlice?
    init(image: NSImage, sourceSize: LSize, mode: WallpaperScalingMode, spanSlice: SpanSlice?) {
        self.sourceSize = sourceSize; self.mode = mode; self.slice = spanSlice; super.init(frame: .zero); wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor; imageLayer.contents = image; imageLayer.contentsGravity = .resize; imageLayer.magnificationFilter = .trilinear; imageLayer.minificationFilter = .trilinear; layer?.addSublayer(imageLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); if let slice { imageLayer.frame = NSRect(x: slice.contentFrameInDisplayPoints.minX, y: slice.contentFrameInDisplayPoints.minY, width: slice.contentFrameInDisplayPoints.size.width, height: slice.contentFrameInDisplayPoints.size.height) } else { let p = GeometryEngine.placement(source: sourceSize, destination: LRect(x: 0, y: 0, width: bounds.width, height: bounds.height), mode: mode); imageLayer.frame = NSRect(x: p.frame.minX, y: p.frame.minY, width: p.frame.size.width, height: p.frame.size.height) } }
}

final class VideoWallpaperView: NSView {
    private let playerLayer = AVPlayerLayer(); private let sourceSize: LSize; private let mode: WallpaperScalingMode; private let slice: SpanSlice?
    init(player: AVPlayer, sourceSize: LSize, mode: WallpaperScalingMode, spanSlice: SpanSlice?) {
        self.sourceSize = sourceSize; self.mode = mode; self.slice = spanSlice; super.init(frame: .zero); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player; playerLayer.videoGravity = .resize; layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); if let slice { playerLayer.frame = NSRect(x: slice.contentFrameInDisplayPoints.minX, y: slice.contentFrameInDisplayPoints.minY, width: slice.contentFrameInDisplayPoints.size.width, height: slice.contentFrameInDisplayPoints.size.height) } else { let p = GeometryEngine.placement(source: sourceSize, destination: LRect(x: 0, y: 0, width: bounds.width, height: bounds.height), mode: mode); playerLayer.frame = NSRect(x: p.frame.minX, y: p.frame.minY, width: p.frame.size.width, height: p.frame.size.height) } }
}
