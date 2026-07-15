import Foundation

public enum DesktopWidgetKind: String, Codable, CaseIterable, Sendable {
    case digitalClock
    case nowPlaying
}

public enum DesktopWidgetSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
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

    public init(showsBackground: Bool = true) {
        self.showsBackground = showsBackground
    }
}

public struct DesktopWidget: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: DesktopWidgetKind
    public var isEnabled: Bool
    public var position: NormalizedWidgetPosition
    public var size: DesktopWidgetSize
    public var digitalClock: DigitalClockWidgetSettings
    public var nowPlaying: NowPlayingWidgetSettings

    public init(
        id: UUID = UUID(),
        kind: DesktopWidgetKind,
        isEnabled: Bool = true,
        position: NormalizedWidgetPosition = NormalizedWidgetPosition(),
        size: DesktopWidgetSize = .medium,
        digitalClock: DigitalClockWidgetSettings = DigitalClockWidgetSettings(),
        nowPlaying: NowPlayingWidgetSettings = NowPlayingWidgetSettings()
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.position = position
        self.size = size
        self.digitalClock = digitalClock
        self.nowPlaying = nowPlaying
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case isEnabled
        case position
        case size
        case digitalClock
        case nowPlaying
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
        digitalClock = try container.decodeIfPresent(
            DigitalClockWidgetSettings.self,
            forKey: .digitalClock
        ) ?? DigitalClockWidgetSettings()
        nowPlaying = try container.decodeIfPresent(
            NowPlayingWidgetSettings.self,
            forKey: .nowPlaying
        ) ?? NowPlayingWidgetSettings()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(position, forKey: .position)
        try container.encode(size, forKey: .size)
        try container.encode(digitalClock, forKey: .digitalClock)
        try container.encode(nowPlaying, forKey: .nowPlaying)
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
