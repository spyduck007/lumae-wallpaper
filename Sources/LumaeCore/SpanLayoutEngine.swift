import Foundation

public struct SpanSlice: Codable, Hashable, Sendable, Identifiable {
    public var id: String { displayID }
    public var displayID: String
    public var displayFrameInVirtualPoints: LRect
    public var contentFrameInDisplayPoints: LRect
    public var sourceCrop: LRect
    public var backingScaleFactor: Double

    public init(
        displayID: String,
        displayFrameInVirtualPoints: LRect,
        contentFrameInDisplayPoints: LRect,
        sourceCrop: LRect,
        backingScaleFactor: Double
    ) {
        self.displayID = displayID
        self.displayFrameInVirtualPoints = displayFrameInVirtualPoints
        self.contentFrameInDisplayPoints = contentFrameInDisplayPoints
        self.sourceCrop = sourceCrop
        self.backingScaleFactor = backingScaleFactor
    }
}

public struct SpanLayout: Codable, Hashable, Sendable {
    public var virtualBoundsPoints: LRect
    public var globalContentFramePoints: LRect
    public var slices: [SpanSlice]

    public init(virtualBoundsPoints: LRect, globalContentFramePoints: LRect, slices: [SpanSlice]) {
        self.virtualBoundsPoints = virtualBoundsPoints
        self.globalContentFramePoints = globalContentFramePoints
        self.slices = slices
    }
}

public enum SpanLayoutError: Error, Equatable, LocalizedError {
    case noDisplays
    case invalidSourceSize
    case invalidDisplayFrame(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplays:
            return "No active displays are available for span mode."
        case .invalidSourceSize:
            return "The wallpaper has invalid or unavailable dimensions."
        case .invalidDisplayFrame(let id):
            return "Display \(id) reported invalid geometry."
        }
    }
}

public enum SpanLayoutEngine {
    public static func makeLayout(
        topology: DisplayTopology,
        sourceSize: LSize,
        mode: WallpaperScalingMode
    ) throws -> SpanLayout {
        guard sourceSize.isValid else { throw SpanLayoutError.invalidSourceSize }
        guard let virtualBounds = topology.virtualBoundsPoints else { throw SpanLayoutError.noDisplays }

        for display in topology.displays where !display.framePoints.isValid {
            throw SpanLayoutError.invalidDisplayFrame(display.id)
        }

        let virtualViewport = LRect(x: 0, y: 0, width: virtualBounds.size.width, height: virtualBounds.size.height)
        let placement = GeometryEngine.placement(source: sourceSize, destination: virtualViewport, mode: mode)

        let slices = topology.displays.map { display -> SpanSlice in
            let displayInVirtual = display.framePoints.translated(dx: -virtualBounds.minX, dy: -virtualBounds.minY)
            let alignedViewport = GeometryEngine.pixelAligned(displayInVirtual, scale: display.backingScaleFactor)
            let localContentFrame = placement.frame.translated(
                dx: -alignedViewport.minX,
                dy: -alignedViewport.minY
            )
            let crop = sourceCrop(
                sourceSize: sourceSize,
                globalContentFrame: placement.frame,
                displayViewport: alignedViewport
            )
            return SpanSlice(
                displayID: display.id,
                displayFrameInVirtualPoints: alignedViewport,
                contentFrameInDisplayPoints: localContentFrame,
                sourceCrop: crop,
                backingScaleFactor: display.backingScaleFactor
            )
        }

        return SpanLayout(
            virtualBoundsPoints: virtualBounds,
            globalContentFramePoints: placement.frame,
            slices: slices
        )
    }

    private static func sourceCrop(
        sourceSize: LSize,
        globalContentFrame: LRect,
        displayViewport: LRect
    ) -> LRect {
        guard let intersection = globalContentFrame.intersection(displayViewport), globalContentFrame.size.isValid else {
            return LRect(x: 0, y: 0, width: 0, height: 0)
        }
        let xScale = sourceSize.width / globalContentFrame.size.width
        let yScale = sourceSize.height / globalContentFrame.size.height
        return LRect(
            x: (intersection.minX - globalContentFrame.minX) * xScale,
            y: (intersection.minY - globalContentFrame.minY) * yScale,
            width: intersection.size.width * xScale,
            height: intersection.size.height * yScale
        )
    }

    public static func maximumBoundaryErrorInPixels(_ layout: SpanLayout) -> Double {
        var maximum = 0.0
        for lhs in layout.slices {
            for rhs in layout.slices where lhs.displayID != rhs.displayID {
                let verticalOverlap = min(lhs.displayFrameInVirtualPoints.maxY, rhs.displayFrameInVirtualPoints.maxY)
                    - max(lhs.displayFrameInVirtualPoints.minY, rhs.displayFrameInVirtualPoints.minY)
                if verticalOverlap > 0 {
                    let gap = abs(lhs.displayFrameInVirtualPoints.maxX - rhs.displayFrameInVirtualPoints.minX)
                    if gap < 1 {
                        maximum = max(maximum, gap * max(lhs.backingScaleFactor, rhs.backingScaleFactor))
                    }
                }

                let horizontalOverlap = min(lhs.displayFrameInVirtualPoints.maxX, rhs.displayFrameInVirtualPoints.maxX)
                    - max(lhs.displayFrameInVirtualPoints.minX, rhs.displayFrameInVirtualPoints.minX)
                if horizontalOverlap > 0 {
                    let gap = abs(lhs.displayFrameInVirtualPoints.maxY - rhs.displayFrameInVirtualPoints.minY)
                    if gap < 1 {
                        maximum = max(maximum, gap * max(lhs.backingScaleFactor, rhs.backingScaleFactor))
                    }
                }
            }
        }
        return maximum
    }
}
