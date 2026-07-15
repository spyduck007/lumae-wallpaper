import AppKit
import AVFoundation
import SwiftUI
import LumaeCore

@MainActor
final class WallpaperWindowManager {
    private var windows: [String: WallpaperWindow] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.restoreDesktopWindowOrder()
                }
            }
        )
        observers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.restoreDesktopWindowOrder()
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.restoreDesktopWindowOrder()
                }
            }
        )
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func removeAll() {
        windows.values.forEach {
            $0.orderOut(nil)
            $0.contentView = nil
        }
        windows.removeAll()
    }

    func showStatic(
        image: NSImage,
        display: DisplayDescriptor,
        sourceSize: LSize,
        mode: WallpaperScalingMode,
        spanSlice: SpanSlice? = nil,
        widgets: [DesktopWidget]
    ) {
        let view = StaticWallpaperView(
            image: image,
            sourceSize: sourceSize,
            mode: mode,
            spanSlice: spanSlice
        )
        install(view: view, display: display, widgets: widgets)
    }

    func showVideo(
        player: AVPlayer,
        display: DisplayDescriptor,
        sourceSize: LSize,
        mode: WallpaperScalingMode,
        spanSlice: SpanSlice? = nil,
        widgets: [DesktopWidget]
    ) {
        let view = VideoWallpaperView(
            player: player,
            sourceSize: sourceSize,
            mode: mode,
            spanSlice: spanSlice
        )
        install(view: view, display: display, widgets: widgets)
    }

    private func install(
        view: NSView,
        display: DisplayDescriptor,
        widgets: [DesktopWidget]
    ) {
        let frame = NSRect(
            x: display.framePoints.minX,
            y: display.framePoints.minY,
            width: display.framePoints.size.width,
            height: display.framePoints.size.height
        )
        let window = WallpaperWindow(contentRect: frame)
        window.contentView = WallpaperCompositeView(
            wallpaperView: view,
            widgets: widgets
        )
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        windows[display.id] = window
    }

    private func restoreDesktopWindowOrder() {
        guard !windows.isEmpty else { return }
        orderWallpaperWindows()

        // macOS may finish rebuilding the desktop stack after the workspace
        // notification is delivered, especially on the built-in display.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.orderWallpaperWindows()
        }
    }

    private func orderWallpaperWindows() {
        for window in windows.values {
            window.orderFrontRegardless()
        }
    }
}

final class WallpaperWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        level = NSWindow.Level(rawValue: desktopIconLevel - 1)
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        sharingType = .none
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        backgroundColor = .black
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WallpaperCompositeView: NSView {
    init(wallpaperView: NSView, widgets: [DesktopWidget]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        wallpaperView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wallpaperView)

        NSLayoutConstraint.activate([
            wallpaperView.leadingAnchor.constraint(equalTo: leadingAnchor),
            wallpaperView.trailingAnchor.constraint(equalTo: trailingAnchor),
            wallpaperView.topAnchor.constraint(equalTo: topAnchor),
            wallpaperView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let enabledWidgets = widgets.filter(\.isEnabled)
        if !enabledWidgets.isEmpty {
            let overlay = NSHostingView(
                rootView: DesktopWidgetOverlayView(widgets: enabledWidgets)
            )
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.wantsLayer = true
            overlay.layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(overlay)

            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
                overlay.topAnchor.constraint(equalTo: topAnchor),
                overlay.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class StaticWallpaperView: NSView {
    private let imageLayer = CALayer()
    private let sourceSize: LSize
    private let mode: WallpaperScalingMode
    private let slice: SpanSlice?

    init(
        image: NSImage,
        sourceSize: LSize,
        mode: WallpaperScalingMode,
        spanSlice: SpanSlice?
    ) {
        self.sourceSize = sourceSize
        self.mode = mode
        self.slice = spanSlice
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .trilinear
        imageLayer.minificationFilter = .trilinear
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        if let slice {
            imageLayer.frame = NSRect(
                x: slice.contentFrameInDisplayPoints.minX,
                y: slice.contentFrameInDisplayPoints.minY,
                width: slice.contentFrameInDisplayPoints.size.width,
                height: slice.contentFrameInDisplayPoints.size.height
            )
        } else {
            let placement = GeometryEngine.placement(
                source: sourceSize,
                destination: LRect(
                    x: 0,
                    y: 0,
                    width: bounds.width,
                    height: bounds.height
                ),
                mode: mode
            )
            imageLayer.frame = NSRect(
                x: placement.frame.minX,
                y: placement.frame.minY,
                width: placement.frame.size.width,
                height: placement.frame.size.height
            )
        }
    }
}

final class VideoWallpaperView: NSView {
    private let playerLayer = AVPlayerLayer()
    private let sourceSize: LSize
    private let mode: WallpaperScalingMode
    private let slice: SpanSlice?

    init(
        player: AVPlayer,
        sourceSize: LSize,
        mode: WallpaperScalingMode,
        spanSlice: SpanSlice?
    ) {
        self.sourceSize = sourceSize
        self.mode = mode
        self.slice = spanSlice
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resize
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        if let slice {
            playerLayer.frame = NSRect(
                x: slice.contentFrameInDisplayPoints.minX,
                y: slice.contentFrameInDisplayPoints.minY,
                width: slice.contentFrameInDisplayPoints.size.width,
                height: slice.contentFrameInDisplayPoints.size.height
            )
        } else {
            let placement = GeometryEngine.placement(
                source: sourceSize,
                destination: LRect(
                    x: 0,
                    y: 0,
                    width: bounds.width,
                    height: bounds.height
                ),
                mode: mode
            )
            playerLayer.frame = NSRect(
                x: placement.frame.minX,
                y: placement.frame.minY,
                width: placement.frame.size.width,
                height: placement.frame.size.height
            )
        }
    }
}
