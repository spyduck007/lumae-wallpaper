import SwiftUI
import LumaeCore

struct DisplayLayoutView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                modeSection

                displayCanvas

                explanation
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Display Layout")
                .font(.largeTitle.bold())

            Text("See how macOS has arranged your displays and choose how Lumae presents wallpapers across them.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presentation Mode")
                .font(.headline)

            Picker("Presentation Mode", selection: $model.state.settings.presentationMode) {
                Label("Per Display", systemImage: "rectangle.split.2x1")
                    .tag(DisplayPresentationMode.perDisplay)
                Label("Duplicate", systemImage: "rectangle.on.rectangle")
                    .tag(DisplayPresentationMode.duplicate)
                Label("Span", systemImage: "rectangle.inset.filled.and.person.filled")
                    .tag(DisplayPresentationMode.span)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var displayCanvas: some View {
        if model.displayTopology.displays.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "display.trianglebadge.exclamationmark")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)

                Text("No Displays Detected")
                    .font(.title3.bold())

                Text("Lumae will refresh this screen automatically when macOS reports an active display.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
            .padding(28)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        } else {
            DisplayTopologyCanvas(topology: model.displayTopology)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }

    private var explanation: some View {
        Label {
            Text("Span mode treats all active displays as one virtual canvas. Duplicate mode shows the same wallpaper independently on each display, while Per Display mode keeps separate assignments.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var modeDescription: String {
        switch model.state.settings.presentationMode {
        case .perDisplay:
            return "Assign a different wallpaper and scaling mode to each display."
        case .duplicate:
            return "Show the same wallpaper on every display while scaling each one independently."
        case .span:
            return "Stretch one synchronized wallpaper across the complete virtual desktop."
        }
    }
}

private struct DisplayTopologyCanvas: View {
    let topology: DisplayTopology

    var body: some View {
        GeometryReader { proxy in
            let bounds = topology.virtualBoundsPoints
                ?? LRect(x: 0, y: 0, width: 1, height: 1)
            let padding = 28.0
            let availableWidth = max(proxy.size.width - padding * 2, 1)
            let availableHeight = max(proxy.size.height - padding * 2, 1)
            let scale = min(
                availableWidth / max(bounds.size.width, 1),
                availableHeight / max(bounds.size.height, 1)
            )
            let renderedWidth = bounds.size.width * scale
            let renderedHeight = bounds.size.height * scale
            let offsetX = (proxy.size.width - renderedWidth) / 2
            let offsetY = (proxy.size.height - renderedHeight) / 2

            ZStack(alignment: .topLeading) {
                ForEach(topology.displays) { display in
                    let width = max(display.framePoints.size.width * scale, 110)
                    let height = max(display.framePoints.size.height * scale, 72)
                    let x = offsetX + (display.framePoints.minX - bounds.minX) * scale
                    let y = offsetY + (bounds.maxY - display.framePoints.maxY) * scale

                    DisplayPreviewCard(display: display)
                        .frame(width: width, height: height)
                        .offset(x: x, y: y)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display arrangement preview")
    }
}

private struct DisplayPreviewCard: View {
    let display: DisplayDescriptor

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                Text(display.fingerprint.localizedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption.bold())

            Text("\(Int(display.pixelSize.width)) × \(Int(display.pixelSize.height))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                Text("\(display.backingScaleFactor, specifier: "%.1f")×")
                if display.isMain {
                    Text("Main")
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.18), in: Capsule())
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.accentColor.opacity(display.isMain ? 0.18 : 0.10),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.accentColor.opacity(display.isMain ? 0.95 : 0.55),
                    lineWidth: display.isMain ? 3 : 1.5
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(display.fingerprint.localizedName), \(Int(display.pixelSize.width)) by \(Int(display.pixelSize.height)) pixels, scale \(display.backingScaleFactor)"
        )
    }
}
