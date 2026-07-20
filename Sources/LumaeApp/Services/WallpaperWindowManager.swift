import AppKit
import AVFoundation
import Combine
import QuartzCore
import SwiftUI
import LumaeCore

@MainActor
final class WallpaperWindowManager {
    var onSystemRevealGesture: (() -> Void)?

    private var windows: [String: WallpaperWindow] = [:]
    private var displayFrames: [String: NSRect] = [:]
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var windowObservers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
    private var eventMonitors: [Any] = []
    private var repairWorkItems: [DispatchWorkItem] = []
    private var replacementSnapshot: ReplacementSnapshot?
    private var watchdogTimer: DispatchSourceTimer?
    private var isScreenLocked = false

    /// Continuously reasserts window level/order independent of any
    /// notification or heuristic, so the real macOS desktop can never stay
    /// visible above the wallpaper for longer than one tick of this
    /// interval, no matter what triggered the reorder — including
    /// transitions we haven't specifically enumerated. Earlier revisions
    /// tried to make this cheaper by only forcing order when a window's
    /// occlusionState indicated it was actually covered, but that signal
    /// isn't reliable for every code path that touches window ordering
    /// (new windows created by a display change, by a Scene switch, by
    /// anything else), and each gap it left showed up later as a fresh
    /// flicker report. Unconditional forcing has no such gaps: it doesn't
    /// need to know why the window might be behind something, only that
    /// it's checked and corrected at a bounded interval, always.
    private static let watchdogInterval: TimeInterval = 0.1

    init() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let notificationCenter = NotificationCenter.default
        let distributedCenter = DistributedNotificationCenter.default()

        observe(
            center: workspaceCenter,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            delays: [0, 0.04, 0.10, 0.20, 0.38, 0.70, 1.10]
        )
        observe(
            center: workspaceCenter,
            name: NSWorkspace.didWakeNotification,
            delays: [0, 0.08, 0.25, 0.60, 1.20]
        )
        observe(
            center: workspaceCenter,
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            delays: [0, 0.08, 0.25, 0.60]
        )
        observe(
            center: notificationCenter,
            name: NSApplication.didBecomeActiveNotification,
            delays: [0, 0.08, 0.22]
        )
        observe(
            center: notificationCenter,
            name: NSApplication.didChangeScreenParametersNotification,
            delays: [0, 0.08, 0.25, 0.60]
        )

        // loginwindow posts this distributed notification tighter to the
        // actual unlock boundary than sessionDidBecomeActiveNotification,
        // which only arrives once the app's own session resumes.
        observeDistributed(
            center: distributedCenter,
            name: Notification.Name("com.apple.screenIsUnlocked"),
            delays: [0, 0.04, 0.10, 0.20, 0.38, 0.70]
        ) { [weak self] in
            self?.isScreenLocked = false
        }

        // While locked, loginwindow fully covers every wallpaper window
        // anyway, so the watchdog has nothing useful to do; skipping it
        // avoids pointless order-front calls for however long the screen
        // stays locked.
        distributedObservers.append(
            distributedCenter.addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isScreenLocked = true
                }
            }
        )

        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.swipe]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onSystemRevealGesture?()
                self?.scheduleRepairBurst(
                    delays: [0, 0.03, 0.08, 0.16, 0.28, 0.48, 0.78]
                )
            }
        } {
            eventMonitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.swipe]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.onSystemRevealGesture?()
                self?.scheduleRepairBurst(
                    delays: [0, 0.03, 0.08, 0.16, 0.28, 0.48, 0.78]
                )
            }
            return event
        } {
            eventMonitors.append(monitor)
        }

        startWatchdog()
    }

    deinit {
        watchdogTimer?.cancel()
        repairWorkItems.forEach { $0.cancel() }
        eventMonitors.forEach(NSEvent.removeMonitor)
        windowObservers.values.flatMap { $0 }.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + Self.watchdogInterval,
            repeating: Self.watchdogInterval,
            leeway: .milliseconds(20)
        )
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.watchdogTick()
            }
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func watchdogTick() {
        // Locked is the one case where skipping is provably safe rather
        // than a heuristic: loginwindow covers every wallpaper window
        // completely for as long as the screen stays locked, so there is
        // nothing for the watchdog to protect against until it unlocks.
        guard !windows.isEmpty, replacementSnapshot == nil, !isScreenLocked else {
            return
        }
        repairWindows(forceOrder: true)
    }

    func beginReplacement() {
        guard replacementSnapshot == nil else { return }
        cancelRepairTasks()
        replacementSnapshot = ReplacementSnapshot(
            windows: windows,
            displayFrames: displayFrames,
            windowObservers: windowObservers
        )
        windows = [:]
        displayFrames = [:]
        windowObservers = [:]
    }

    func commitReplacement() {
        guard let snapshot = replacementSnapshot else { return }
        replacementSnapshot = nil

        repairWindows(forceOrder: true)
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.retire(snapshot)
            }
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.08,
            execute: workItem
        )
        scheduleRepairBurst(delays: [0.02, 0.10, 0.24])
    }

    func rollbackReplacement() {
        guard let snapshot = replacementSnapshot else { return }
        replacementSnapshot = nil
        retireCurrentWindows()
        windows = snapshot.windows
        displayFrames = snapshot.displayFrames
        windowObservers = snapshot.windowObservers
        repairWindows(forceOrder: true)
        scheduleRepairBurst(delays: [0.03, 0.12, 0.30])
    }

    func removeAll() {
        cancelRepairTasks()
        if let snapshot = replacementSnapshot {
            retire(snapshot)
            replacementSnapshot = nil
        }
        retireCurrentWindows()
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
        displayFrames[display.id] = frame
        windows[display.id] = window
        observeWindow(window)
        repairWindow(window, expectedFrame: frame, forceOrder: true)
        scheduleRepairBurst(delays: [0.03, 0.12, 0.30])
    }

    func updateWidgets(_ widgetsByDisplayID: [String: [DesktopWidget]]) {
        for (displayID, window) in windows {
            guard let composite = window.contentView as? WallpaperCompositeView else {
                continue
            }
            composite.updateWidgets(widgetsByDisplayID[displayID] ?? [])
        }
    }

    func setPerformanceSuspended(
        _ suspendedDisplayIDs: Set<String>
    ) {
        for (displayID, window) in windows {
            guard let composite = window.contentView as? WallpaperCompositeView else {
                continue
            }
            composite.setPerformanceSuspended(
                suspendedDisplayIDs.contains(displayID)
            )
        }
    }

    private func retireCurrentWindows() {
        let snapshot = ReplacementSnapshot(
            windows: windows,
            displayFrames: displayFrames,
            windowObservers: windowObservers
        )
        windows = [:]
        displayFrames = [:]
        windowObservers = [:]
        retire(snapshot)
    }

    private func retire(_ snapshot: ReplacementSnapshot) {
        snapshot.windowObservers.values.flatMap { $0 }.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        snapshot.windows.values.forEach {
            $0.orderOut(nil)
            $0.contentView = nil
        }
    }

    private func observeWindow(_ window: WallpaperWindow) {
        let center = NotificationCenter.default
        let tokens = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didResizeNotification
        ].map { name in
            center.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleRepairBurst(
                        delays: [0, 0.04, 0.12, 0.28]
                    )
                }
            }
        }
        windowObservers[ObjectIdentifier(window)] = tokens
    }

    private func observe(
        center: NotificationCenter,
        name: Notification.Name,
        delays: [TimeInterval]
    ) {
        observers.append(
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleRepairBurst(delays: delays)
                }
            }
        )
    }

    private func observeDistributed(
        center: DistributedNotificationCenter,
        name: Notification.Name,
        delays: [TimeInterval],
        before: (@MainActor @Sendable () -> Void)? = nil
    ) {
        distributedObservers.append(
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    before?()
                    self?.scheduleRepairBurst(delays: delays)
                }
            }
        )
    }

    private func scheduleRepairBurst(delays: [TimeInterval]) {
        guard !windows.isEmpty else { return }
        cancelRepairTasks()
        repairWindows(forceOrder: true)

        repairWorkItems = delays.filter { $0 > 0 }.map { delay in
            let workItem = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.repairWindows(forceOrder: true)
                }
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: workItem
            )
            return workItem
        }
    }

    private func cancelRepairTasks() {
        repairWorkItems.forEach { $0.cancel() }
        repairWorkItems.removeAll()
    }

    private func repairWindows(forceOrder: Bool) {
        for (displayID, window) in windows {
            let expectedFrame = displayFrames[displayID] ?? window.frame
            repairWindow(
                window,
                expectedFrame: expectedFrame,
                forceOrder: forceOrder
            )
        }
    }

    private func repairWindow(
        _ window: WallpaperWindow,
        expectedFrame: NSRect,
        forceOrder: Bool
    ) {
        window.enforceWallpaperBehavior()

        if window.frame != expectedFrame {
            window.setFrame(expectedFrame, display: true, animate: false)
            window.contentView?.needsLayout = true
        }
        if !window.isVisible || forceOrder {
            window.orderFrontRegardless()
        }
    }
}

private struct ReplacementSnapshot {
    var windows: [String: WallpaperWindow]
    var displayFrames: [String: NSRect]
    var windowObservers: [ObjectIdentifier: [NSObjectProtocol]]
}

final class WallpaperWindow: NSWindow {
    private static let wallpaperLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1
    )

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        enforceWallpaperBehavior()
    }

    func enforceWallpaperBehavior() {
        level = Self.wallpaperLevel
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        sharingType = .readOnly
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        backgroundColor = .black
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        canHide = false
        isMovable = false
        isMovableByWindowBackground = false
    }

    override var worksWhenModal: Bool { true }
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
    private var isPerformanceSuspended = false
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

    func setPerformanceSuspended(_ suspended: Bool) {
        guard isPerformanceSuspended != suspended else { return }
        isPerformanceSuspended = suspended
        glassBackdrop.isHidden = suspended || glassBackdrop.maskImage == nil
        contrastBackdrop.isHidden = suspended || contrastBackdrop.maskImage == nil
        for host in widgetHosts.values {
            host.isHidden = suspended
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
                host.isHidden = isPerformanceSuspended
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
        if isPerformanceSuspended {
            glassBackdrop.isHidden = true
            contrastBackdrop.isHidden = true
        }
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
        case .dateCalendar, .battery, .weather:
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
        case (.dateCalendar, .small), (.battery, .small), (.weather, .small): return 16 * 0.78
        case (.dateCalendar, .medium), (.battery, .medium), (.weather, .medium): return 20
        case (.dateCalendar, .large), (.battery, .large), (.weather, .large): return 20 * 1.30
        case (.dateCalendar, .custom), (.battery, .custom), (.weather, .custom): return 20 * scale
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
