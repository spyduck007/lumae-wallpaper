import Foundation

public enum DesktopWidgetKind: String, Codable, CaseIterable, Sendable {
    case digitalClock
    case nowPlaying
    case dateCalendar
    case battery
}

public enum DesktopWidgetSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
    case custom
}


public enum WidgetVisualStyle: String, Codable, CaseIterable, Hashable, Sendable {
    case glass
    case clear
    case highContrast
    case none
}

public enum WidgetDisplayMode: String, Codable, CaseIterable, Sendable {
    case mirrored
    case perDisplay
}

public struct NormalizedWidgetPosition: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double = 0.5, y: Double = 0.18) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

public struct DigitalClockWidgetSettings: Codable, Hashable, Sendable {
    public var uses24HourTime: Bool
    public var showsSeconds: Bool
    public var showsBackground: Bool

    public init(
        uses24HourTime: Bool = false,
        showsSeconds: Bool = false,
        showsBackground: Bool = true
    ) {
        self.uses24HourTime = uses24HourTime
        self.showsSeconds = showsSeconds
        self.showsBackground = showsBackground
    }

    private enum CodingKeys: String, CodingKey {
        case uses24HourTime
        case showsSeconds
        case showsBackground
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uses24HourTime = try container.decodeIfPresent(
            Bool.self,
            forKey: .uses24HourTime
        ) ?? false
        showsSeconds = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsSeconds
        ) ?? false
        showsBackground = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsBackground
        ) ?? true
    }
}


public struct NowPlayingWidgetSettings: Codable, Hashable, Sendable {
    public var showsBackground: Bool
    public var usesArtworkTint: Bool

    public init(
        showsBackground: Bool = true,
        usesArtworkTint: Bool = true
    ) {
        self.showsBackground = showsBackground
        self.usesArtworkTint = usesArtworkTint
    }

    private enum CodingKeys: String, CodingKey {
        case showsBackground
        case usesArtworkTint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsBackground = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsBackground
        ) ?? true
        usesArtworkTint = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesArtworkTint
        ) ?? true
    }
}


public enum DateCalendarWidgetMode: String, Codable, CaseIterable, Sendable {
    case compactDate
    case fullDate
    case monthCalendar
}

public enum CalendarWeekStart: String, Codable, CaseIterable, Sendable {
    case system
    case sunday
    case monday
}

public struct DateCalendarWidgetSettings: Codable, Hashable, Sendable {
    public var mode: DateCalendarWidgetMode
    public var showsWeekday: Bool
    public var showsYear: Bool
    public var weekStart: CalendarWeekStart
    public var showsAdjacentMonthDates: Bool
    public var showsBackground: Bool

    public init(
        mode: DateCalendarWidgetMode = .compactDate,
        showsWeekday: Bool = true,
        showsYear: Bool = false,
        weekStart: CalendarWeekStart = .system,
        showsAdjacentMonthDates: Bool = true,
        showsBackground: Bool = true
    ) {
        self.mode = mode
        self.showsWeekday = showsWeekday
        self.showsYear = showsYear
        self.weekStart = weekStart
        self.showsAdjacentMonthDates = showsAdjacentMonthDates
        self.showsBackground = showsBackground
    }
}

public struct BatteryWidgetSettings: Codable, Hashable, Sendable {
    public var showsPercentage: Bool
    public var showsStatusText: Bool
    public var showsProgressBar: Bool
    public var showsBackground: Bool

    public init(
        showsPercentage: Bool = true,
        showsStatusText: Bool = true,
        showsProgressBar: Bool = true,
        showsBackground: Bool = true
    ) {
        self.showsPercentage = showsPercentage
        self.showsStatusText = showsStatusText
        self.showsProgressBar = showsProgressBar
        self.showsBackground = showsBackground
    }
}

public struct DesktopWidget: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: DesktopWidgetKind
    public var isEnabled: Bool
    public var position: NormalizedWidgetPosition
    public var size: DesktopWidgetSize
    public var customScale: Double?
    public var style: WidgetVisualStyle
    public var digitalClock: DigitalClockWidgetSettings
    public var nowPlaying: NowPlayingWidgetSettings
    public var dateCalendar: DateCalendarWidgetSettings
    public var battery: BatteryWidgetSettings

    public init(
        id: UUID = UUID(),
        kind: DesktopWidgetKind,
        isEnabled: Bool = true,
        position: NormalizedWidgetPosition = NormalizedWidgetPosition(),
        size: DesktopWidgetSize = .medium,
        customScale: Double? = nil,
        style: WidgetVisualStyle = .glass,
        digitalClock: DigitalClockWidgetSettings = DigitalClockWidgetSettings(),
        nowPlaying: NowPlayingWidgetSettings = NowPlayingWidgetSettings(),
        dateCalendar: DateCalendarWidgetSettings = DateCalendarWidgetSettings(),
        battery: BatteryWidgetSettings = BatteryWidgetSettings()
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.position = position
        self.size = size
        self.customScale = customScale.map(Self.clampedCustomScale)
        self.style = style
        self.digitalClock = digitalClock
        self.nowPlaying = nowPlaying
        self.dateCalendar = dateCalendar
        self.battery = battery
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case isEnabled
        case position
        case size
        case customScale
        case style
        case digitalClock
        case nowPlaying
        case dateCalendar
        case battery
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(DesktopWidgetKind.self, forKey: .kind)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        position = try container.decodeIfPresent(
            NormalizedWidgetPosition.self,
            forKey: .position
        ) ?? NormalizedWidgetPosition()
        size = try container.decodeIfPresent(
            DesktopWidgetSize.self,
            forKey: .size
        ) ?? .medium
        customScale = try container.decodeIfPresent(
            Double.self,
            forKey: .customScale
        ).map(Self.clampedCustomScale)
        digitalClock = try container.decodeIfPresent(
            DigitalClockWidgetSettings.self,
            forKey: .digitalClock
        ) ?? DigitalClockWidgetSettings()
        nowPlaying = try container.decodeIfPresent(
            NowPlayingWidgetSettings.self,
            forKey: .nowPlaying
        ) ?? NowPlayingWidgetSettings()
        dateCalendar = try container.decodeIfPresent(
            DateCalendarWidgetSettings.self,
            forKey: .dateCalendar
        ) ?? DateCalendarWidgetSettings()
        battery = try container.decodeIfPresent(
            BatteryWidgetSettings.self,
            forKey: .battery
        ) ?? BatteryWidgetSettings()
        style = try container.decodeIfPresent(
            WidgetVisualStyle.self,
            forKey: .style
        ) ?? Self.legacyStyle(
            kind: kind,
            digitalClock: digitalClock,
            nowPlaying: nowPlaying,
            dateCalendar: dateCalendar,
            battery: battery
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(position, forKey: .position)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(customScale, forKey: .customScale)
        try container.encode(style, forKey: .style)
        try container.encode(digitalClock, forKey: .digitalClock)
        try container.encode(nowPlaying, forKey: .nowPlaying)
        try container.encode(dateCalendar, forKey: .dateCalendar)
        try container.encode(battery, forKey: .battery)
    }

    private static func legacyStyle(
        kind: DesktopWidgetKind,
        digitalClock: DigitalClockWidgetSettings,
        nowPlaying: NowPlayingWidgetSettings,
        dateCalendar: DateCalendarWidgetSettings,
        battery: BatteryWidgetSettings
    ) -> WidgetVisualStyle {
        let showedBackground: Bool
        switch kind {
        case .digitalClock:
            showedBackground = digitalClock.showsBackground
        case .nowPlaying:
            showedBackground = nowPlaying.showsBackground
        case .dateCalendar:
            showedBackground = dateCalendar.showsBackground
        case .battery:
            showedBackground = battery.showsBackground
        }
        return showedBackground ? .glass : .none
    }

    public var renderingScale: Double {
        guard size == .custom else { return 1 }
        return Self.clampedCustomScale(customScale ?? 1)
    }

    public static func clampedCustomScale(_ scale: Double) -> Double {
        min(max(scale, 0.45), 2.5)
    }

    public func duplicated() -> DesktopWidget {
        var copy = self
        copy.id = UUID()
        return copy
    }
}

public struct WidgetDisplayConfiguration: Identifiable, Codable, Hashable, Sendable {
    public var id: String { displayFingerprint.stableID }
    public var displayFingerprint: DisplayFingerprint
    public var isEnabled: Bool
    public var widgets: [DesktopWidget]

    public init(
        displayFingerprint: DisplayFingerprint,
        isEnabled: Bool = true,
        widgets: [DesktopWidget] = []
    ) {
        self.displayFingerprint = displayFingerprint
        self.isEnabled = isEnabled
        self.widgets = widgets
    }
}

public enum WidgetDisplayResolver {
    public static func widgets(
        for display: DisplayDescriptor,
        mode: WidgetDisplayMode,
        mirroredWidgets: [DesktopWidget],
        configurations: [WidgetDisplayConfiguration],
        excludingConfigurationIDs: Set<String> = []
    ) -> [DesktopWidget] {
        let configuration = bestConfiguration(
            for: display.fingerprint,
            in: configurations,
            excludingConfigurationIDs: excludingConfigurationIDs
        )

        switch mode {
        case .mirrored:
            guard configuration?.isEnabled != false else { return [] }
            return mirroredWidgets

        case .perDisplay:
            guard let configuration, configuration.isEnabled else { return [] }
            return configuration.widgets
        }
    }

    public static func bestConfiguration(
        for fingerprint: DisplayFingerprint,
        in configurations: [WidgetDisplayConfiguration],
        minimumFallbackScore: Int = 200,
        excludingConfigurationIDs: Set<String> = []
    ) -> WidgetDisplayConfiguration? {
        if let exact = configurations.first(where: {
            $0.displayFingerprint.stableID == fingerprint.stableID
        }) {
            return exact
        }

        let candidates = configurations
            .filter { !excludingConfigurationIDs.contains($0.id) }
            .map { configuration in
            (
                configuration,
                configuration.displayFingerprint.matchScore(against: fingerprint)
            )
        }.filter { $0.1 >= minimumFallbackScore }

        guard let best = candidates.max(by: { $0.1 < $1.1 }) else { return nil }
        guard candidates.filter({ $0.1 == best.1 }).count == 1 else { return nil }
        return best.0
    }
}


public struct WidgetSnapResult: Hashable, Sendable {
    public var position: NormalizedWidgetPosition
    public var verticalGuide: Double?
    public var horizontalGuide: Double?

    public init(
        position: NormalizedWidgetPosition,
        verticalGuide: Double? = nil,
        horizontalGuide: Double? = nil
    ) {
        self.position = position
        self.verticalGuide = verticalGuide
        self.horizontalGuide = horizontalGuide
    }
}

public enum WidgetSnapEngine {
    public static func snap(
        position: NormalizedWidgetPosition,
        canvasSize: LSize,
        verticalTargets: [Double] = [0.10, 0.50, 0.90],
        horizontalTargets: [Double] = [0.12, 0.50, 0.88],
        thresholdPoints: Double = 10
    ) -> WidgetSnapResult {
        let verticalGuide = nearestTarget(
            to: position.x,
            targets: verticalTargets,
            dimension: canvasSize.width,
            thresholdPoints: thresholdPoints
        )
        let horizontalGuide = nearestTarget(
            to: position.y,
            targets: horizontalTargets,
            dimension: canvasSize.height,
            thresholdPoints: thresholdPoints
        )

        return WidgetSnapResult(
            position: NormalizedWidgetPosition(
                x: verticalGuide ?? position.x,
                y: horizontalGuide ?? position.y
            ),
            verticalGuide: verticalGuide,
            horizontalGuide: horizontalGuide
        )
    }

    private static func nearestTarget(
        to value: Double,
        targets: [Double],
        dimension: Double,
        thresholdPoints: Double
    ) -> Double? {
        guard dimension > 0,
              let nearest = targets.min(by: {
                  abs($0 - value) < abs($1 - value)
              }),
              abs(nearest - value) * dimension <= thresholdPoints else {
            return nil
        }
        return nearest
    }
}

public struct WidgetCanvasItem: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var frame: LRect

    public init(id: UUID, frame: LRect) {
        self.id = id
        self.frame = frame
    }
}

public struct WidgetCanvasSnapResult: Hashable, Sendable {
    public var frame: LRect
    public var verticalGuides: [Double]
    public var horizontalGuides: [Double]
    public var hasEqualHorizontalSpacing: Bool
    public var hasEqualVerticalSpacing: Bool

    public init(
        frame: LRect,
        verticalGuides: [Double] = [],
        horizontalGuides: [Double] = [],
        hasEqualHorizontalSpacing: Bool = false,
        hasEqualVerticalSpacing: Bool = false
    ) {
        self.frame = frame
        self.verticalGuides = verticalGuides
        self.horizontalGuides = horizontalGuides
        self.hasEqualHorizontalSpacing = hasEqualHorizontalSpacing
        self.hasEqualVerticalSpacing = hasEqualVerticalSpacing
    }
}

public enum WidgetCanvasEngine {
    public static func snap(
        moving: WidgetCanvasItem,
        canvasSize: LSize,
        others: [WidgetCanvasItem],
        thresholdPoints: Double = 8
    ) -> WidgetCanvasSnapResult {
        guard canvasSize.isValid, moving.frame.isValid else {
            return WidgetCanvasSnapResult(frame: moving.frame)
        }
        var xCandidates: [(Double, Double, Bool)] = []
        var yCandidates: [(Double, Double, Bool)] = []
        xCandidates.append((0 - moving.frame.minX, 0, false))
        xCandidates.append((canvasSize.width / 2 - moving.frame.midX, canvasSize.width / 2, false))
        xCandidates.append((canvasSize.width - moving.frame.maxX, canvasSize.width, false))
        yCandidates.append((0 - moving.frame.minY, 0, false))
        yCandidates.append((canvasSize.height / 2 - moving.frame.midY, canvasSize.height / 2, false))
        yCandidates.append((canvasSize.height - moving.frame.maxY, canvasSize.height, false))
        for other in others {
            xCandidates.append((other.frame.minX - moving.frame.minX, other.frame.minX, false))
            xCandidates.append((other.frame.midX - moving.frame.midX, other.frame.midX, false))
            xCandidates.append((other.frame.maxX - moving.frame.maxX, other.frame.maxX, false))
            xCandidates.append((other.frame.maxX - moving.frame.minX, other.frame.maxX, false))
            xCandidates.append((other.frame.minX - moving.frame.maxX, other.frame.minX, false))

            yCandidates.append((other.frame.minY - moving.frame.minY, other.frame.minY, false))
            yCandidates.append((other.frame.midY - moving.frame.midY, other.frame.midY, false))
            yCandidates.append((other.frame.maxY - moving.frame.maxY, other.frame.maxY, false))
            yCandidates.append((other.frame.maxY - moving.frame.minY, other.frame.maxY, false))
            yCandidates.append((other.frame.minY - moving.frame.maxY, other.frame.minY, false))
        }
        if others.count >= 2 {
            for left in others {
                for right in others where left.id != right.id && left.frame.maxX <= right.frame.minX {
                    let available = right.frame.minX - left.frame.maxX - moving.frame.size.width
                    if available >= 0 {
                        let desired = left.frame.maxX + available / 2
                        xCandidates.append((desired - moving.frame.minX, desired + moving.frame.size.width / 2, true))
                    }
                }
            }
            for top in others {
                for bottom in others where top.id != bottom.id && top.frame.maxY <= bottom.frame.minY {
                    let available = bottom.frame.minY - top.frame.maxY - moving.frame.size.height
                    if available >= 0 {
                        let desired = top.frame.maxY + available / 2
                        yCandidates.append((desired - moving.frame.minY, desired + moving.frame.size.height / 2, true))
                    }
                }
            }
        }
        let bestX = xCandidates.filter { abs($0.0) <= thresholdPoints }.min { abs($0.0) < abs($1.0) }
        let bestY = yCandidates.filter { abs($0.0) <= thresholdPoints }.min { abs($0.0) < abs($1.0) }
        let bounded = clamp(
            moving.frame.translated(dx: bestX?.0 ?? 0, dy: bestY?.0 ?? 0),
            to: canvasSize
        )
        return WidgetCanvasSnapResult(
            frame: bounded,
            verticalGuides: bestX.map { [$0.1] } ?? [],
            horizontalGuides: bestY.map { [$0.1] } ?? [],
            hasEqualHorizontalSpacing: bestX?.2 ?? false,
            hasEqualVerticalSpacing: bestY?.2 ?? false
        )
    }

    public static func clamp(_ frame: LRect, to canvasSize: LSize) -> LRect {
        guard canvasSize.isValid, frame.isValid else { return frame }
        let width = min(frame.size.width, canvasSize.width)
        let height = min(frame.size.height, canvasSize.height)
        return LRect(
            x: min(max(frame.minX, 0), canvasSize.width - width),
            y: min(max(frame.minY, 0), canvasSize.height - height),
            width: width,
            height: height
        )
    }

    public static func maximumScale(
        currentFrame: LRect,
        currentScale: Double,
        center: LPoint,
        canvasSize: LSize
    ) -> Double {
        guard currentFrame.isValid, currentScale > 0, canvasSize.isValid else { return currentScale }
        let availableWidth = 2 * min(center.x, canvasSize.width - center.x)
        let availableHeight = 2 * min(center.y, canvasSize.height - center.y)
        return max(0.01, currentScale * min(
            availableWidth / currentFrame.size.width,
            availableHeight / currentFrame.size.height
        ))
    }
}
