import AppKit
import AVFoundation
import Combine
import QuartzCore
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

    func updateWidgets(_ widgetsByDisplayID: [String: [DesktopWidget]]) {
        for (displayID, window) in windows {
            guard let composite = window.contentView as? WallpaperCompositeView else {
                continue
            }
            composite.updateWidgets(widgetsByDisplayID[displayID] ?? [])
        }
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
    private let wallpaperView: NSView
    private let glassBackdrop = SharedWidgetBackdropView(
        material: .underWindowBackground,
        opacity: 0.52
    )
    private let contrastBackdrop = SharedWidgetBackdropView(
        material: .popover,
        opacity: 0.92
    )
    private var widgetHosts: [UUID: DesktopWidgetHostingView] = [:]
    private var widgets: [DesktopWidget] = []
    private var accessibilityObserver: NSObjectProtocol?

    override var isFlipped: Bool { true }

    init(wallpaperView: NSView, widgets: [DesktopWidget]) {
        self.wallpaperView = wallpaperView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.drawsAsynchronously = true

        wallpaperView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wallpaperView)
        NSLayoutConstraint.activate([
            wallpaperView.leadingAnchor.constraint(equalTo: leadingAnchor),
            wallpaperView.trailingAnchor.constraint(equalTo: trailingAnchor),
            wallpaperView.topAnchor.constraint(equalTo: topAnchor),
            wallpaperView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        configureBackdrop(glassBackdrop, above: wallpaperView)
        configureBackdrop(contrastBackdrop, above: glassBackdrop)
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.needsLayout = true
            }
        }
        updateWidgets(widgets)
    }

    deinit {
        if let accessibilityObserver {
            NotificationCenter.default.removeObserver(accessibilityObserver)
        }
    }

    func updateWidgets(_ widgets: [DesktopWidget]) {
        let enabledWidgets = widgets.filter(\.isEnabled)
        guard self.widgets != enabledWidgets else { return }

        let previousWidgets = Dictionary(
            uniqueKeysWithValues: self.widgets.map { ($0.id, $0) }
        )
        let previousOrder = self.widgets.map(\.id)
        let newOrder = enabledWidgets.map(\.id)
        self.widgets = enabledWidgets

        let validIDs = Set(newOrder)
        let removedIDs = widgetHosts.keys.filter { !validIDs.contains($0) }
        for id in removedIDs {
            widgetHosts.removeValue(forKey: id)?.removeFromSuperview()
        }

        var createdHost = false
        for widget in enabledWidgets {
            let host: DesktopWidgetHostingView
            if let existing = widgetHosts[widget.id] {
                if previousWidgets[widget.id] != widget {
                    existing.rootView = DesktopWidgetHostContent(widget: widget)
                }
                host = existing
            } else {
                host = DesktopWidgetHostingView(
                    rootView: DesktopWidgetHostContent(widget: widget)
                )
                host.wantsLayer = true
                host.layer?.backgroundColor = NSColor.clear.cgColor
                host.layer?.drawsAsynchronously = true
                host.translatesAutoresizingMaskIntoConstraints = true
                widgetHosts[widget.id] = host
                createdHost = true
            }

            host.layer?.shouldRasterize = shouldRasterize(widget)
            host.layer?.rasterizationScale = window?.backingScaleFactor ?? 2
        }

        if previousOrder != newOrder || createdHost || !removedIDs.isEmpty {
            for host in widgetHosts.values {
                host.removeFromSuperview()
            }
            var previousView: NSView = contrastBackdrop
            for widget in enabledWidgets {
                guard let host = widgetHosts[widget.id] else { continue }
                addSubview(host, positioned: .above, relativeTo: previousView)
                previousView = host
            }
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        glassBackdrop.frame = bounds
        contrastBackdrop.frame = bounds
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        var glassRegions: [WidgetBackdropRegion] = []
        var contrastRegions: [WidgetBackdropRegion] = []

        for widget in widgets {
            guard let host = widgetHosts[widget.id] else { continue }
            host.layoutSubtreeIfNeeded()
            var size = host.fittingSize
            if size.width <= 0 || size.height <= 0 {
                size = host.intrinsicContentSize
            }
            guard size.width > 0, size.height > 0 else { continue }

            let desired = CGPoint(
                x: bounds.width * CGFloat(widget.position.x),
                y: bounds.height * CGFloat(widget.position.y)
            )
            var frame = CGRect(
                x: desired.x - size.width / 2,
                y: desired.y - size.height / 2,
                width: size.width,
                height: size.height
            )
            frame.origin.x = min(max(frame.origin.x, 0), max(bounds.width - frame.width, 0))
            frame.origin.y = min(max(frame.origin.y, 0), max(bounds.height - frame.height, 0))
            host.frame = frame.integral
            host.layer?.rasterizationScale = window?.backingScaleFactor ?? 2

            let region = WidgetBackdropRegion(
                frame: host.frame,
                cornerRadius: desktopCornerRadius(for: widget).rounded(.toNearestOrAwayFromZero)
            )
            switch widget.style {
            case .glass where !reduceTransparency:
                glassRegions.append(region)
            case .highContrast where !reduceTransparency:
                contrastRegions.append(region)
            case .glass, .highContrast:
                break
            case .clear, .none:
                break
            }
        }

        glassBackdrop.update(regions: glassRegions, canvasSize: bounds.size)
        contrastBackdrop.update(regions: contrastRegions, canvasSize: bounds.size)
        CATransaction.commit()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func configureBackdrop(
        _ backdrop: SharedWidgetBackdropView,
        above sibling: NSView
    ) {
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        addSubview(backdrop, positioned: .above, relativeTo: sibling)
    }

    private func shouldRasterize(_ widget: DesktopWidget) -> Bool {
        switch widget.kind {
        case .nowPlaying:
            return false
        case .digitalClock:
            return !widget.digitalClock.showsSeconds
        case .dateCalendar, .battery:
            return true
        }
    }

    private func desktopCornerRadius(for widget: DesktopWidget) -> CGFloat {
        let scale = CGFloat(widget.renderingScale)
        switch (widget.kind, widget.size) {
        case (.digitalClock, .small): return 16
        case (.digitalClock, .medium): return 20
        case (.digitalClock, .large): return 25
        case (.digitalClock, .custom): return 20 * scale
        case (.nowPlaying, .small): return 16
        case (.nowPlaying, .medium): return 21
        case (.nowPlaying, .large): return 27
        case (.nowPlaying, .custom): return 21 * scale
        case (.dateCalendar, .small), (.battery, .small): return 16 * 0.78
        case (.dateCalendar, .medium), (.battery, .medium): return 20
        case (.dateCalendar, .large), (.battery, .large): return 20 * 1.30
        case (.dateCalendar, .custom), (.battery, .custom): return 20 * scale
        }
    }
}

final class DesktopWidgetHostingView: NSHostingView<DesktopWidgetHostContent> {
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        superview?.needsLayout = true
    }
}

private struct WidgetBackdropRegion: Equatable {
    var frame: CGRect
    var cornerRadius: CGFloat
}

final class SharedWidgetBackdropView: NSVisualEffectView {
    private var regions: [WidgetBackdropRegion] = []
    private var canvasSize: CGSize = .zero

    init(material: NSVisualEffectView.Material, opacity: CGFloat) {
        super.init(frame: .zero)
        self.material = material
        blendingMode = .withinWindow
        state = .active
        isEmphasized = false
        alphaValue = opacity
        wantsLayer = true
        layer?.drawsAsynchronously = true
        isHidden = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    fileprivate func update(
        regions: [WidgetBackdropRegion],
        canvasSize: CGSize
    ) {
        guard self.regions != regions || self.canvasSize != canvasSize else { return }
        self.regions = regions
        self.canvasSize = canvasSize
        isHidden = regions.isEmpty
        guard !regions.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else {
            maskImage = nil
            return
        }
        maskImage = makeMask(regions: regions, canvasSize: canvasSize)
    }

    private func makeMask(
        regions: [WidgetBackdropRegion],
        canvasSize: CGSize
    ) -> NSImage {
        let image = NSImage(
            size: canvasSize,
            flipped: true
        ) { _ in
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: canvasSize).fill()
            NSColor.white.setFill()
            for region in regions {
                NSBezierPath(
                    roundedRect: region.frame,
                    xRadius: region.cornerRadius,
                    yRadius: region.cornerRadius
                ).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
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
        imageLayer.drawsAsynchronously = true
        imageLayer.isOpaque = true
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let targetFrame: NSRect
        if let slice {
            targetFrame = NSRect(
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
            targetFrame = NSRect(
                x: placement.frame.minX,
                y: placement.frame.minY,
                width: placement.frame.size.width,
                height: placement.frame.size.height
            )
        }
        if imageLayer.frame != targetFrame {
            imageLayer.frame = targetFrame
        }
        CATransaction.commit()
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
        playerLayer.drawsAsynchronously = true
        playerLayer.isOpaque = true
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let targetFrame: NSRect
        if let slice {
            targetFrame = NSRect(
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
            targetFrame = NSRect(
                x: placement.frame.minX,
                y: placement.frame.minY,
                width: placement.frame.size.width,
                height: placement.frame.size.height
            )
        }
        if playerLayer.frame != targetFrame {
            playerLayer.frame = targetFrame
        }
        CATransaction.commit()
    }
}
