import SwiftUI
import LumaeCore

struct DisplayLayoutView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    headerText
                    Spacer(minLength: 24)
                    modePicker
                }

                VStack(alignment: .leading, spacing: 14) {
                    headerText
                    modePicker
                }
            }

            GeometryReader { proxy in
                let topology = model.displayService.currentTopology
                let bounds = topology.virtualBoundsPoints
                    ?? LRect(x: 0, y: 0, width: 1, height: 1)
                let availableWidth = max(proxy.size.width - 56, 1)
                let availableHeight = max(proxy.size.height - 56, 1)
                let scale = max(
                    0.01,
                    min(
                        availableWidth / max(bounds.size.width, 1),
                        availableHeight / max(bounds.size.height, 1)
                    )
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)

                    if topology.displays.isEmpty {
                        ContentUnavailableView(
                            "No Displays Found",
                            systemImage: "display.trianglebadge.exclamationmark",
                            description: Text("Lumae will update automatically when a display becomes available.")
                        )
                    } else {
                        ForEach(topology.displays) { display in
                            let x = (display.framePoints.minX - bounds.minX) * scale + 28
                            let y = (bounds.maxY - display.framePoints.maxY) * scale + 28
                            let width = max(display.framePoints.size.width * scale, 90)
                            let height = max(display.framePoints.size.height * scale, 58)

                            DisplayPreviewCard(display: display)
                                .frame(width: width, height: height)
                                .position(
                                    x: x + width / 2,
                                    y: y + height / 2
                                )
                        }
                    }
                }
            }
            .frame(minHeight: 320)

            Label {
                Text("Span mode maps one source across the full virtual desktop, then crops the correct synchronized region for each display.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Display Layout")
                .font(.largeTitle.bold())

            Text("Assignments use stable display fingerprints and are restored conservatively when monitors reconnect.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modePicker: some View {
        Picker("Presentation mode", selection: $model.state.settings.presentationMode) {
            Text("Per Display").tag(DisplayPresentationMode.perDisplay)
            Text("Duplicate").tag(DisplayPresentationMode.duplicate)
            Text("Span").tag(DisplayPresentationMode.span)
        }
        .pickerStyle(.segmented)
        .frame(width: 300)
        .help("Choose how wallpapers are assigned across displays")
    }
}

private struct DisplayPreviewCard: View {
    let display: DisplayDescriptor

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(0.13))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(display.isMain ? 0.95 : 0.55),
                        lineWidth: display.isMain ? 3 : 1.5
                    )
            }
            .overlay {
                VStack(spacing: 5) {
                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                        .font(.title3)

                    Text(display.fingerprint.localizedName)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("\(Int(display.pixelSize.width)) × \(Int(display.pixelSize.height)) · \(display.backingScaleFactor, specifier: "%.1f")×")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Display \(display.fingerprint.localizedName), \(Int(display.pixelSize.width)) by \(Int(display.pixelSize.height)) pixels"
            )
    }
}
