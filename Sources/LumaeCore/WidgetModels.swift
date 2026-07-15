import Foundation

public enum DesktopWidgetKind: String, Codable, CaseIterable, Sendable {
    case digitalClock
}

public enum DesktopWidgetSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
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

    public init(
        uses24HourTime: Bool = false,
        showsSeconds: Bool = false
    ) {
        self.uses24HourTime = uses24HourTime
        self.showsSeconds = showsSeconds
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
}
