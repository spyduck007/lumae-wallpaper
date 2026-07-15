import AppKit
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
                } else {
                    WidgetBackdropBlur(
                        material: material,
                        blendingMode: .withinWindow
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
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private var increaseContrast: Bool {
        colorSchemeContrast == .increased
    }

    private var resolvedStyle: WidgetVisualStyle {
        increaseContrast && style != .none ? .highContrast : style
    }

    private var material: NSVisualEffectView.Material {
        switch resolvedStyle {
        case .glass: return .hudWindow
        case .clear: return .underWindowBackground
        case .highContrast: return .popover
        case .none: return .underWindowBackground
        }
    }

    private var baseTint: Color {
        switch resolvedStyle {
        case .glass: return .black.opacity(0.10)
        case .clear: return .black.opacity(0.025)
        case .highContrast: return .black.opacity(0.62)
        case .none: return .clear
        }
    }

    private var solidFallbackColor: Color {
        switch resolvedStyle {
        case .glass, .clear: return .black.opacity(0.70)
        case .highContrast: return .black.opacity(0.84)
        case .none: return .clear
        }
    }

    private var artworkTintOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.16
        case .clear: return 0.09
        case .highContrast, .none: return 0
        }
    }

    private var highlightOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.22
        case .clear: return 0.13
        case .highContrast: return 0.18
        case .none: return 0
        }
    }

    private var bottomShadeOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.10
        case .clear: return 0.035
        case .highContrast: return 0.18
        case .none: return 0
        }
    }

    private var noiseOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.055
        case .clear: return 0.030
        case .highContrast: return 0.025
        case .none: return 0
        }
    }

    private var borderHighlightOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.34
        case .clear: return 0.22
        case .highContrast: return 0.40
        case .none: return 0
        }
    }

    private var borderLowOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.10
        case .clear: return 0.06
        case .highContrast: return 0.20
        case .none: return 0
        }
    }

    private var innerShadowOpacity: Double {
        switch resolvedStyle {
        case .glass: return 0.20
        case .clear: return 0.10
        case .highContrast: return 0.28
        case .none: return 0
        }
    }
}

private struct WidgetBackdropBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.isEmphasized = false
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
    }
}

private struct WidgetNoiseTexture: View {
    let opacity: Double

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            guard opacity > 0, size.width > 0, size.height > 0 else { return }
            let pointCount = min(max(Int(size.width * size.height / 650), 80), 420)
            for index in 0..<pointCount {
                let x = hash(index * 17 + 11) * size.width
                let y = hash(index * 31 + 7) * size.height
                let alpha = opacity * (0.35 + hash(index * 13 + 5) * 0.65)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 0.8, height: 0.8)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
    }

    private func hash(_ value: Int) -> CGFloat {
        let x = sin(Double(value) * 12.9898) * 43_758.5453
        return CGFloat(x - floor(x))
    }
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
                color: style == .none
                    ? .black.opacity(0.50)
                    : .black.opacity(style == .highContrast ? 0.34 : 0.24),
                radius: (style == .none ? 7 : 14) * scale,
                y: (style == .none ? 2 : 5) * scale
            )
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
