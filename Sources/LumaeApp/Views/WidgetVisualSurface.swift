import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import LumaeCore

struct WidgetVisualSurface: View {
    let style: WidgetVisualStyle
    let cornerRadius: CGFloat
    var tint: Color? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        ZStack {
            if resolvedStyle != .none {
                if reduceTransparency {
                    shape.fill(solidFallbackColor)
                } else if resolvedStyle != .clear {
                    WidgetBackdropBlur(
                        material: material,
                        blendingMode: .withinWindow,
                        effectOpacity: effectOpacity
                    )
                    .clipShape(shape)
                }

                shape.fill(baseTint)

                if let tint, resolvedStyle != .highContrast {
                    shape.fill(tint.opacity(artworkTintOpacity))
                        .blendMode(.softLight)
                }

                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(highlightOpacity), location: 0),
                        .init(color: .white.opacity(0.018), location: 0.34),
                        .init(color: .clear, location: 0.62),
                        .init(color: .black.opacity(bottomShadeOpacity), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(shape)

                WidgetNoiseTexture(opacity: noiseOpacity)
                    .clipShape(shape)
                    .blendMode(.softLight)

                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(borderHighlightOpacity),
                                .white.opacity(borderLowOpacity),
                                .black.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: increaseContrast ? 1.5 : 1
                    )

                shape
                    .stroke(.black.opacity(innerShadowOpacity), lineWidth: 1)
                    .blur(radius: 1.2)
                    .offset(y: 1)
                    .mask(shape)
            }
        }
        .allowsHitTesting(false)
    }

    private var increaseContrast: Bool {
        colorSchemeContrast == .increased
    }

    private var resolvedStyle: WidgetVisualStyle {
        increaseContrast && style != .none ? .highContrast : style
    }

    private var effectOpacity: CGFloat {
        switch resolvedStyle {
        case .glass: return 0.52
        case .clear: return 0
        case .highContrast: return 0.92
        case .none: return 0
        }
    }

    private var material: NSVisualEffectView.Material {
        switch resolvedStyle {
        case .glass: return .underWindowBackground
        case .clear: return .underWindowBackground
        case .highContrast: return .popover
        case .none: return .underWindowBackground
        }
    }

    private var baseTint: Color {
        switch resolvedStyle {
        case .glass: return .black.opacity(0.015)
        case .clear: return .white.opacity(0.006)
        case .highContrast: return .black.opacity(0.62)
        case .none: return .clear
        }
    }

    private var solidFallbackColor: Color {
        switch resolvedStyle {
        case .glass: return .black.opacity(0.62)
        case .clear: return .black.opacity(0.42)
        case .highContrast: return .black.opacity(0.84)
        case .none: return .clear
        }
    }

    private var artworkTintOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.13
        case .clear: return 0.045
        case .highContrast, .none: return 0
        }
    }

    private var highlightOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.30
        case .clear: return 0.09
        case .highContrast: return 0.18
        case .none: return 0
        }
    }

    private var bottomShadeOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.055
        case .clear: return 0.008
        case .highContrast: return 0.18
        case .none: return 0
        }
    }

    private var noiseOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.032
        case .clear: return 0.008
        case .highContrast: return 0.025
        case .none: return 0
        }
    }

    private var borderHighlightOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.48
        case .clear: return 0.16
        case .highContrast: return 0.40
        case .none: return 0
        }
    }

    private var borderLowOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.08
        case .clear: return 0.025
        case .highContrast: return 0.20
        case .none: return 0
        }
    }

    private var innerShadowOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.16
        case .clear: return 0.045
        case .highContrast: return 0.28
        case .none: return 0
        }
    }
}

private struct WidgetBackdropBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let effectOpacity: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.isEmphasized = false
        view.material = material
        view.blendingMode = blendingMode
        view.alphaValue = effectOpacity
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        view.alphaValue = effectOpacity
    }
}

private struct WidgetNoiseTexture: View {
    let opacity: Double

    var body: some View {
        Image(nsImage: WidgetNoiseAsset.image)
            .resizable(capInsets: EdgeInsets(), resizingMode: .tile)
            .interpolation(.none)
            .opacity(opacity)
    }
}

private enum WidgetNoiseAsset {
    static let image: NSImage = {
        let size = 64
        let filter = CIFilter.randomGenerator()
        guard let output = filter.outputImage?.cropped(
            to: CGRect(x: 0, y: 0, width: size, height: size)
        ) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        let context = CIContext()
        guard let cgImage = context.createCGImage(
            output,
            from: output.extent
        ) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: size, height: size)
        )
    }()
}

private struct WidgetSurfaceModifier: ViewModifier {
    let style: WidgetVisualStyle
    let cornerRadius: CGFloat
    let scale: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                WidgetVisualSurface(
                    style: style,
                    cornerRadius: cornerRadius,
                    tint: tint
                )
            }
            .shadow(
                color: shadowColor,
                radius: shadowRadius * scale,
                y: shadowOffset * scale
            )
    }

    private var shadowColor: Color {
        switch style {
        case .glass: return .black.opacity(0.20)
        case .clear: return .black.opacity(0.12)
        case .highContrast: return .black.opacity(0.32)
        case .none: return .black.opacity(0.46)
        }
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .glass: return 10
        case .clear: return 6
        case .highContrast: return 12
        case .none: return 5
        }
    }

    private var shadowOffset: CGFloat {
        style == .none ? 2 : 4
    }
}

extension View {
    func widgetSurface(
        style: WidgetVisualStyle,
        cornerRadius: CGFloat,
        scale: CGFloat = 1,
        tint: Color? = nil
    ) -> some View {
        modifier(
            WidgetSurfaceModifier(
                style: style,
                cornerRadius: cornerRadius,
                scale: scale,
                tint: tint
            )
        )
    }
}
