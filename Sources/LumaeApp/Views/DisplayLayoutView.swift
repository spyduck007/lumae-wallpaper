import SwiftUI
import AppKit
import LumaeCore

struct DisplayLayoutView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                modeSection
                displayCanvas
                configurationSection
                explanation
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if model.selectedDisplayID == nil {
                model.selectedDisplayID = model.displayTopology.displays
                    .first(where: { $0.isMain })?.id
                    ?? model.displayTopology.displays.first?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Display Layout")
                .font(.largeTitle.bold())

            Text("See how macOS arranged your displays and control what Lumae shows on each one.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presentation Mode")
                .font(.headline)

            Picker(
                "Presentation Mode",
                selection: Binding(
                    get: { model.state.settings.presentationMode },
                    set: { model.setPresentationMode($0) }
                )
            ) {
                Label("Per Display", systemImage: "rectangle.split.2x1")
                    .tag(DisplayPresentationMode.perDisplay)
                Label("Duplicate", systemImage: "rectangle.on.rectangle")
                    .tag(DisplayPresentationMode.duplicate)
                Label("Span", systemImage: "rectangle.inset.filled")
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

                Text("Lumae refreshes this screen automatically when macOS reports an active display.")
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
            DisplayTopologyCanvas(
                topology: model.displayTopology,
                selectedDisplayID: $model.selectedDisplayID,
                assignments: assignmentMap,
                wallpapers: wallpaperMap,
                selectionEnabled: model.state.settings.presentationMode == .perDisplay
            )
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

    @ViewBuilder
    private var configurationSection: some View {
        switch model.state.settings.presentationMode {
        case .perDisplay:
            perDisplayConfiguration
        case .duplicate:
            SharedDisplayConfigurationCard(
                title: "Duplicate Wallpaper",
                description: "Each display receives a complete copy of this wallpaper and scales it independently.",
                wallpaperID: Binding(
                    get: { model.state.sharedWallpaperID },
                    set: { model.setSharedWallpaper($0) }
                ),
                scalingMode: Binding(
                    get: { model.state.settings.defaultScalingMode },
                    set: { model.setDefaultScalingMode($0) }
                ),
                wallpapers: model.assignableWallpapers,
                previewMode: .duplicate
            )
        case .span:
            SharedDisplayConfigurationCard(
                title: "Spanned Wallpaper",
                description: "Lumae treats the display arrangement above as one canvas and shows the matching slice on each screen.",
                wallpaperID: Binding(
                    get: { model.state.sharedWallpaperID },
                    set: { model.setSharedWallpaper($0) }
                ),
                scalingMode: Binding(
                    get: { model.state.settings.defaultScalingMode },
                    set: { model.setDefaultScalingMode($0) }
                ),
                wallpapers: model.assignableWallpapers,
                previewMode: .span
            )
        }
    }

    @ViewBuilder
    private var perDisplayConfiguration: some View {
        if let display = selectedDisplay {
            let assignment = model.displayAssignment(for: display)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.fingerprint.localizedName)
                            .font(.title3.bold())

                        Text(displaySummary(display))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle(
                        "Enabled",
                        isOn: Binding(
                            get: { assignment.enabled },
                            set: { model.setDisplayEnabled($0, for: display.id) }
                        )
                    )
                    .toggleStyle(.switch)
                }

                Divider()

                HStack(alignment: .top, spacing: 18) {
                    WallpaperPreview(
                        wallpaper: model.wallpaper(id: assignment.wallpaperID),
                        mode: .single
                    )
                    .frame(width: 230, height: 144)

                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("Wallpaper") {
                            WallpaperPicker(
                                selection: Binding(
                                    get: { assignment.wallpaperID },
                                    set: { model.setDisplayWallpaper($0, for: display.id) }
                                ),
                                wallpapers: model.assignableWallpapers,
                                includesNone: true
                            )
                            .frame(width: 260)
                        }

                        LabeledContent("Scaling") {
                            ScalingModePicker(
                                selection: Binding(
                                    get: { assignment.scalingMode },
                                    set: { model.setDisplayScalingMode($0, for: display.id) }
                                )
                            )
                            .frame(width: 170)
                        }

                        HStack(spacing: 10) {
                            Button("Use Shared Wallpaper") {
                                model.setDisplayWallpaper(
                                    model.state.sharedWallpaperID,
                                    for: display.id
                                )
                            }
                            .disabled(model.state.sharedWallpaperID == nil)

                            Button("Use on All Displays") {
                                model.state.sharedWallpaperID = assignment.wallpaperID
                                model.applySharedWallpaperToAllDisplays()
                            }
                            .disabled(assignment.wallpaperID == nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(!assignment.enabled)
                .opacity(assignment.enabled ? 1 : 0.55)
            }
            .padding(18)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        } else {
            Text("Select a display above to configure it.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(30)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
    }

    private var explanation: some View {
        Label {
            Text(explanationText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var selectedDisplay: DisplayDescriptor? {
        guard let selectedDisplayID = model.selectedDisplayID else { return nil }
        return model.displayTopology.display(id: selectedDisplayID)
    }

    private var assignmentMap: [String: DisplayAssignment] {
        Dictionary(
            uniqueKeysWithValues: model.displayTopology.displays.map { display in
                if model.state.settings.presentationMode == .perDisplay {
                    return (display.id, model.displayAssignment(for: display))
                }

                return (
                    display.id,
                    DisplayAssignment(
                        displayFingerprint: display.fingerprint,
                        wallpaperID: model.state.sharedWallpaperID,
                        enabled: true,
                        scalingMode: model.state.settings.defaultScalingMode
                    )
                )
            }
        )
    }

    private var wallpaperMap: [UUID: WallpaperMetadata] {
        Dictionary(uniqueKeysWithValues: model.state.wallpapers.map { ($0.id, $0) })
    }

    private var modeDescription: String {
        switch model.state.settings.presentationMode {
        case .perDisplay:
            return "Select a display in the diagram, then assign its wallpaper and scaling mode below."
        case .duplicate:
            return "Show one complete wallpaper on every display, scaled independently for each screen."
        case .span:
            return "Treat all active displays as one virtual canvas and divide one wallpaper across them."
        }
    }

    private var explanationText: String {
        switch model.state.settings.presentationMode {
        case .perDisplay:
            return "Assignments are matched back to displays using their hardware fingerprint, so reconnecting a monitor restores its wallpaper when possible."
        case .duplicate:
            return "Duplicate mode uses one synchronized source. Different display shapes may show different crops when Fill is selected."
        case .span:
            return "For the best span result, use a wallpaper whose aspect ratio is close to the complete display arrangement shown above."
        }
    }

    private func displaySummary(_ display: DisplayDescriptor) -> String {
        var parts = [
            "\(Int(display.pixelSize.width)) × \(Int(display.pixelSize.height))",
            String(format: "%.1f×", display.backingScaleFactor)
        ]
        if display.isMain { parts.append("Main display") }
        if display.isBuiltIn { parts.append("Built-in") }
        return parts.joined(separator: " • ")
    }
}

private struct DisplayTopologyCanvas: View {
    let topology: DisplayTopology
    @Binding var selectedDisplayID: String?
    let assignments: [String: DisplayAssignment]
    let wallpapers: [UUID: WallpaperMetadata]
    let selectionEnabled: Bool

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
                    let x = offsetX
                        + (display.framePoints.minX - bounds.minX) * scale
                    let y = offsetY
                        + (bounds.maxY - display.framePoints.maxY) * scale
                    let assignment = assignments[display.id]
                    let wallpaper = assignment?.wallpaperID.flatMap { wallpapers[$0] }
                    let selected = selectionEnabled && selectedDisplayID == display.id

                    DisplayPreviewCard(
                        display: display,
                        assignment: assignment,
                        wallpaper: wallpaper,
                        selected: selected,
                        selectionEnabled: selectionEnabled
                    )
                    .frame(width: width, height: height)
                    .offset(x: x, y: y)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard selectionEnabled else { return }
                        selectedDisplayID = display.id
                    }
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display arrangement preview")
    }
}

private struct DisplayPreviewCard: View {
    let display: DisplayDescriptor
    let assignment: DisplayAssignment?
    let wallpaper: WallpaperMetadata?
    let selected: Bool
    let selectionEnabled: Bool

    var body: some View {
        ZStack {
            previewBackground

            Color.black.opacity(wallpaper == nil ? 0.05 : 0.28)

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

                if let wallpaper {
                    Text(wallpaper.name)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if assignment?.enabled == false {
                    Label("Disabled", systemImage: "pause.circle")
                        .font(.caption2.weight(.semibold))
                } else {
                    Text("No wallpaper")
                        .font(.caption2)
                }

                HStack(spacing: 5) {
                    Text("\(display.backingScaleFactor, specifier: "%.1f")×")
                    if display.isMain {
                        Text("Main")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.22), in: Capsule())
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    selected
                        ? Color.accentColor
                        : Color.accentColor.opacity(display.isMain ? 0.9 : 0.55),
                    lineWidth: selected ? 4 : (display.isMain ? 3 : 1.5)
                )
        }
        .shadow(
            color: selected ? Color.accentColor.opacity(0.25) : .clear,
            radius: 8
        )
        .opacity(assignment?.enabled == false ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: selected)
        .help(selectionEnabled ? "Select this display" : display.fingerprint.localizedName)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var previewBackground: some View {
        if let thumbnailPath = wallpaper?.thumbnailPath,
           let image = NSImage(contentsOfFile: thumbnailPath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.accentColor.opacity(display.isMain ? 0.18 : 0.10)
        }
    }

    private var accessibilityDescription: String {
        var description = "\(display.fingerprint.localizedName), \(Int(display.pixelSize.width)) by \(Int(display.pixelSize.height)) pixels"
        if let wallpaper {
            description += ", assigned \(wallpaper.name)"
        } else {
            description += ", no wallpaper assigned"
        }
        return description
    }
}

private enum WallpaperPreviewMode {
    case single
    case duplicate
    case span
}

private struct SharedDisplayConfigurationCard: View {
    let title: String
    let description: String
    @Binding var wallpaperID: UUID?
    @Binding var scalingMode: WallpaperScalingMode
    let wallpapers: [WallpaperMetadata]
    let previewMode: WallpaperPreviewMode

    private var wallpaper: WallpaperMetadata? {
        wallpapers.first { $0.id == wallpaperID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(alignment: .top, spacing: 18) {
                WallpaperPreview(wallpaper: wallpaper, mode: previewMode)
                    .frame(width: 260, height: 162)

                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("Wallpaper") {
                        WallpaperPicker(
                            selection: $wallpaperID,
                            wallpapers: wallpapers,
                            includesNone: true
                        )
                        .frame(width: 280)
                    }

                    LabeledContent("Scaling") {
                        ScalingModePicker(selection: $scalingMode)
                            .frame(width: 170)
                    }

                    Text(scalingDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var scalingDescription: String {
        switch scalingMode {
        case .fill:
            return "Fill covers every display area and may crop the wallpaper."
        case .fit:
            return "Fit preserves the complete wallpaper and may add black bars."
        case .stretch:
            return "Stretch fills the available area without preserving aspect ratio."
        case .center:
            return "Center keeps the wallpaper at its original pixel dimensions."
        }
    }
}

private struct WallpaperPicker: View {
    @Binding var selection: UUID?
    let wallpapers: [WallpaperMetadata]
    let includesNone: Bool

    var body: some View {
        Picker("Wallpaper", selection: $selection) {
            if includesNone {
                Text("None").tag(Optional<UUID>.none)
                Divider()
            }

            ForEach(wallpapers) { wallpaper in
                Label(
                    wallpaper.name,
                    systemImage: wallpaper.kind == .video ? "play.rectangle" : "photo"
                )
                .tag(Optional(wallpaper.id))
            }
        }
        .labelsHidden()
    }
}

private struct ScalingModePicker: View {
    @Binding var selection: WallpaperScalingMode

    var body: some View {
        Picker("Scaling", selection: $selection) {
            ForEach(WallpaperScalingMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .labelsHidden()
    }
}

private struct WallpaperPreview: View {
    let wallpaper: WallpaperMetadata?
    let mode: WallpaperPreviewMode

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)

            if let thumbnailPath = wallpaper?.thumbnailPath,
               let image = NSImage(contentsOfFile: thumbnailPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title)
                    Text("No Wallpaper")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }

            previewOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var previewOverlay: some View {
        switch mode {
        case .single:
            EmptyView()
        case .duplicate:
            HStack(spacing: 8) {
                previewScreen
                previewScreen
            }
            .padding(18)
        case .span:
            HStack(spacing: 2) {
                previewScreen
                previewScreen
            }
            .padding(18)
        }
    }

    private var previewScreen: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
    }
}

private extension WallpaperScalingMode {
    var label: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        case .center: return "Center"
        }
    }
}
