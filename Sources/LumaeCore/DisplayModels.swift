import Foundation

public struct DisplayFingerprint: Codable, Hashable, Sendable {
    public var stableID: String
    public var vendorID: UInt32?
    public var modelID: UInt32?
    public var serialNumber: UInt32?
    public var localizedName: String

    public init(
        stableID: String,
        vendorID: UInt32? = nil,
        modelID: UInt32? = nil,
        serialNumber: UInt32? = nil,
        localizedName: String
    ) {
        self.stableID = stableID
        self.vendorID = vendorID
        self.modelID = modelID
        self.serialNumber = serialNumber
        self.localizedName = localizedName
    }

    public func matchScore(against other: DisplayFingerprint) -> Int {
        if stableID == other.stableID { return 1_000 }
        var score = 0
        if let serialNumber, serialNumber != 0, serialNumber == other.serialNumber { score += 500 }
        if let vendorID, vendorID == other.vendorID { score += 120 }
        if let modelID, modelID == other.modelID { score += 120 }
        if localizedName.caseInsensitiveCompare(other.localizedName) == .orderedSame { score += 40 }
        return score
    }
}

public struct DisplayDescriptor: Codable, Hashable, Sendable, Identifiable {
    public var id: String { fingerprint.stableID }
    public var fingerprint: DisplayFingerprint
    public var framePoints: LRect
    public var visibleFramePoints: LRect
    public var pixelSize: LSize
    public var backingScaleFactor: Double
    public var refreshRate: Double?
    public var rotationDegrees: Double
    public var isMain: Bool
    public var isBuiltIn: Bool
    public var mirroredDisplayID: String?

    public init(
        fingerprint: DisplayFingerprint,
        framePoints: LRect,
        visibleFramePoints: LRect,
        pixelSize: LSize,
        backingScaleFactor: Double,
        refreshRate: Double? = nil,
        rotationDegrees: Double = 0,
        isMain: Bool = false,
        isBuiltIn: Bool = false,
        mirroredDisplayID: String? = nil
    ) {
        self.fingerprint = fingerprint
        self.framePoints = framePoints
        self.visibleFramePoints = visibleFramePoints
        self.pixelSize = pixelSize
        self.backingScaleFactor = backingScaleFactor
        self.refreshRate = refreshRate
        self.rotationDegrees = rotationDegrees
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.mirroredDisplayID = mirroredDisplayID
    }
}

public struct DisplayTopology: Codable, Hashable, Sendable {
    public var displays: [DisplayDescriptor]
    public var capturedAt: Date

    public init(displays: [DisplayDescriptor], capturedAt: Date = Date()) {
        self.displays = displays.sorted { lhs, rhs in
            if lhs.framePoints.minX == rhs.framePoints.minX {
                return lhs.framePoints.minY < rhs.framePoints.minY
            }
            return lhs.framePoints.minX < rhs.framePoints.minX
        }
        self.capturedAt = capturedAt
    }

    public var virtualBoundsPoints: LRect? {
        LRect.union(displays.map(\.framePoints))
    }

    public var activeDisplayIDs: Set<String> {
        Set(displays.map(\.id))
    }

    public func display(id: String) -> DisplayDescriptor? {
        displays.first { $0.id == id }
    }
}

public enum DisplayPresentationMode: String, Codable, CaseIterable, Sendable {
    case perDisplay
    case duplicate
    case span
}

public struct DisplayAssignment: Codable, Hashable, Sendable, Identifiable {
    public var id: String { displayFingerprint.stableID }
    public var displayFingerprint: DisplayFingerprint
    public var wallpaperID: UUID?
    public var enabled: Bool
    public var scalingMode: WallpaperScalingMode
    public var maxFrameRate: Int?
    public var videoQuality: VideoQuality

    public init(
        displayFingerprint: DisplayFingerprint,
        wallpaperID: UUID? = nil,
        enabled: Bool = true,
        scalingMode: WallpaperScalingMode = .fill,
        maxFrameRate: Int? = nil,
        videoQuality: VideoQuality = .balanced
    ) {
        self.displayFingerprint = displayFingerprint
        self.wallpaperID = wallpaperID
        self.enabled = enabled
        self.scalingMode = scalingMode
        self.maxFrameRate = maxFrameRate
        self.videoQuality = videoQuality
    }
}

public enum VideoQuality: String, Codable, CaseIterable, Sendable {
    case efficiency
    case balanced
    case quality
}

public enum DisplayAssignmentRestorer {
    public static func restore(
        saved: [DisplayAssignment],
        onto topology: DisplayTopology,
        minimumFallbackScore: Int = 200
    ) -> [String: DisplayAssignment] {
        var result: [String: DisplayAssignment] = [:]
        var remaining = saved

        for display in topology.displays {
            if let exactIndex = remaining.firstIndex(where: { $0.displayFingerprint.stableID == display.id }) {
                result[display.id] = remaining.remove(at: exactIndex)
                continue
            }

            let candidates = remaining.enumerated().map { index, assignment in
                (index, assignment, assignment.displayFingerprint.matchScore(against: display.fingerprint))
            }.filter { $0.2 >= minimumFallbackScore }

            guard let best = candidates.max(by: { $0.2 < $1.2 }) else { continue }
            let sameScoreCount = candidates.filter { $0.2 == best.2 }.count
            guard sameScoreCount == 1 else { continue }
            result[display.id] = remaining.remove(at: best.0)
        }

        return result
    }
}


public enum PlaybackSuspensionPolicy {
    public static func shouldPause(
        sessionDisplayIDs: Set<String>,
        coveredDisplayIDs: Set<String>,
        manuallyPaused: Bool
    ) -> Bool {
        manuallyPaused || (
            !sessionDisplayIDs.isEmpty
                && sessionDisplayIDs.isSubset(of: coveredDisplayIDs)
        )
    }
}
