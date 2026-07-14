import Foundation

public struct LPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct LSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public var isValid: Bool { width > 0 && height > 0 && width.isFinite && height.isFinite }
    public var aspectRatio: Double { isValid ? width / height : 0 }
}

public struct LRect: Codable, Hashable, Sendable {
    public var origin: LPoint
    public var size: LSize

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = LPoint(x: x, y: y)
        self.size = LSize(width: width, height: height)
    }

    public init(origin: LPoint, size: LSize) {
        self.origin = origin
        self.size = size
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }
    public var isValid: Bool { size.isValid && origin.x.isFinite && origin.y.isFinite }

    public func translated(dx: Double, dy: Double) -> LRect {
        LRect(x: origin.x + dx, y: origin.y + dy, width: size.width, height: size.height)
    }

    public func intersection(_ other: LRect) -> LRect? {
        let x1 = max(minX, other.minX)
        let y1 = max(minY, other.minY)
        let x2 = min(maxX, other.maxX)
        let y2 = min(maxY, other.maxY)
        guard x2 > x1, y2 > y1 else { return nil }
        return LRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    public static func union(_ rects: [LRect]) -> LRect? {
        let valid = rects.filter(\.isValid)
        guard let first = valid.first else { return nil }
        return valid.dropFirst().reduce(first) { current, next in
            LRect(
                x: min(current.minX, next.minX),
                y: min(current.minY, next.minY),
                width: max(current.maxX, next.maxX) - min(current.minX, next.minX),
                height: max(current.maxY, next.maxY) - min(current.minY, next.minY)
            )
        }
    }
}

public enum WallpaperScalingMode: String, Codable, CaseIterable, Sendable {
    case fill
    case fit
    case stretch
    case center
}

public struct ContentPlacement: Codable, Hashable, Sendable {
    public var frame: LRect
    public var visibleCropInSource: LRect

    public init(frame: LRect, visibleCropInSource: LRect) {
        self.frame = frame
        self.visibleCropInSource = visibleCropInSource
    }
}

public enum GeometryEngine {
    public static func placement(
        source: LSize,
        destination: LRect,
        mode: WallpaperScalingMode
    ) -> ContentPlacement {
        guard source.isValid, destination.isValid else {
            return ContentPlacement(
                frame: LRect(x: destination.minX, y: destination.minY, width: 0, height: 0),
                visibleCropInSource: LRect(x: 0, y: 0, width: 0, height: 0)
            )
        }

        switch mode {
        case .stretch:
            return ContentPlacement(
                frame: destination,
                visibleCropInSource: LRect(x: 0, y: 0, width: source.width, height: source.height)
            )
        case .center:
            let frame = LRect(
                x: destination.midX - source.width / 2,
                y: destination.midY - source.height / 2,
                width: source.width,
                height: source.height
            )
            return ContentPlacement(frame: frame, visibleCropInSource: crop(source: source, frame: frame, viewport: destination))
        case .fit, .fill:
            let widthScale = destination.size.width / source.width
            let heightScale = destination.size.height / source.height
            let scale = mode == .fit ? min(widthScale, heightScale) : max(widthScale, heightScale)
            let scaled = LSize(width: source.width * scale, height: source.height * scale)
            let frame = LRect(
                x: destination.midX - scaled.width / 2,
                y: destination.midY - scaled.height / 2,
                width: scaled.width,
                height: scaled.height
            )
            return ContentPlacement(frame: frame, visibleCropInSource: crop(source: source, frame: frame, viewport: destination))
        }
    }

    private static func crop(source: LSize, frame: LRect, viewport: LRect) -> LRect {
        guard let visible = frame.intersection(viewport), frame.size.isValid else {
            return LRect(x: 0, y: 0, width: 0, height: 0)
        }
        let sx = source.width / frame.size.width
        let sy = source.height / frame.size.height
        return LRect(
            x: (visible.minX - frame.minX) * sx,
            y: (visible.minY - frame.minY) * sy,
            width: visible.size.width * sx,
            height: visible.size.height * sy
        )
    }

    public static func pixelAligned(_ value: Double, scale: Double) -> Double {
        guard scale > 0, scale.isFinite else { return value }
        return (value * scale).rounded() / scale
    }

    public static func pixelAligned(_ rect: LRect, scale: Double) -> LRect {
        let minX = pixelAligned(rect.minX, scale: scale)
        let minY = pixelAligned(rect.minY, scale: scale)
        let maxX = pixelAligned(rect.maxX, scale: scale)
        let maxY = pixelAligned(rect.maxY, scale: scale)
        return LRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}
