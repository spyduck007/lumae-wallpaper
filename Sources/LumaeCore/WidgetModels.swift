import Foundation

public enum DesktopWidgetKind: String, Codable, CaseIterable, Sendable {
    case digitalClock
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

public struct DesktopWidget: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: DesktopWidgetKind
    public var isEnabled: Bool
    public var position: NormalizedWidgetPosition
    public var size: DesktopWidgetSize
    public var digitalClock: DigitalClockWidgetSettings

    public init(
        id: UUID = UUID(),
        kind: DesktopWidgetKind,
        isEnabled: Bool = true,
        position: NormalizedWidgetPosition = NormalizedWidgetPosition(),
        size: DesktopWidgetSize = .medium,
        digitalClock: DigitalClockWidgetSettings = DigitalClockWidgetSettings()
    ) {
        self.id = id
        self.kind = kind
        self.isEnabled = isEnabled
        self.position = position
        self.size = size
        self.digitalClock = digitalClock
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
        configurations: [WidgetDisplayConfiguration]
    ) -> [DesktopWidget] {
        let configuration = bestConfiguration(
            for: display.fingerprint,
            in: configurations
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
        minimumFallbackScore: Int = 200
    ) -> WidgetDisplayConfiguration? {
        if let exact = configurations.first(where: {
            $0.displayFingerprint.stableID == fingerprint.stableID
        }) {
            return exact
        }

        let candidates = configurations.map { configuration in
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
