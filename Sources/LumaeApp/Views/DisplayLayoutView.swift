import SwiftUI
import AppKit
import LumaeCore

struct DisplayLayoutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    modeSection
                    displayCanvas
                    modeExplanation
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()

            inspector
                .frame(width: 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: selectInitialDisplayIfNeeded)
        .onChange(of: model.displayTopology) { _, _ in
            selectInitialDisplayIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Display Layout")
                .font(.largeTitle.bold())

            Text("Control how Lumae presents wallpapers across your connected displays.")
                .foregroundStyle(.secondary)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Presentation Mode")
                    .font(.headline)

                Spacer()

                Label("Applies immediately", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
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
                .fixedSize()

                Spacer(minLength: 0)
            }
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

                Text("Lumae refreshes automatically when macOS reports an active display.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 390)
            .canvasCard()
        } else {
            DisplayTopologyCanvas(
                topology: model.displayTopology,
                selectedDisplayID: $model.selectedDisplayID,
                assignments: assignmentMap,
                wallpapers: wallpaperMap,
                presentationMode: model.state.settings.presentationMode
            )
            .frame(maxWidth: .infinity)
            .frame(height: 420)
            .canvasCard()
        }
    }

    private var modeExplanation: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: modeIcon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 5) {
                Text(modeTitle)
                    .font(.headline)

                Text(modeDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(modeExample)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.accentColor.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch model.state.settings.presentationMode {
                case .perDisplay:
                    perDisplayInspector
                case .duplicate:
                    sharedInspector(mode: .duplicate)
                case .span:
                    sharedInspector(mode: .span)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
    }

    @ViewBuilder
    private var perDisplayInspector: some View {
        if let display = selectedDisplay {
            let assignment = model.displayAssignment(for: display)
            let wallpaper = model.wallpaper(id: assignment.wallpaperID)

            InspectorHeader(
                title: display.fingerprint.localizedName,
                subtitle: displaySummary(display),
                systemImage: display.isBuiltIn ? "laptopcomputer" : "display"
            )

            WallpaperPreview(wallpaper: wallpaper, mode: .single)
                .frame(height: 176)

            Toggle(
                "Enable wallpaper on this display",
                isOn: Binding(
                    get: { assignment.enabled },
                    set: { model.setDisplayEnabled($0, for: display.id) }
                )
            )
            .toggleStyle(.switch)

            Divider()

            InspectorField(title: "Wallpaper") {
                WallpaperPicker(
                    selection: Binding(
                        get: { assignment.wallpaperID },
                        set: { model.setDisplayWallpaper($0, for: display.id) }
                    ),
                    wallpapers: model.assignableWallpapers,
                    includesNone: true
                )
            }

            InspectorField(title: "Scaling") {
                ScalingModePicker(
                    selection: Binding(
                        get: { assignment.scalingMode },
                        set: { model.setDisplayScalingMode($0, for: display.id) }
                    )
                )
            }

            Text(assignment.scalingMode.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button("Use Shared Wallpaper") {
                model.setDisplayWallpaper(
                    model.state.sharedWallpaperID,
                    for: display.id
                )
            }
            .frame(maxWidth: .infinity)
            .disabled(model.state.sharedWallpaperID == nil)

            Button("Use This Wallpaper on All Displays") {
                model.state.sharedWallpaperID = assignment.wallpaperID
                model.applySharedWallpaperToAllDisplays()
            }
            .frame(maxWidth: .infinity)
            .disabled(assignment.wallpaperID == nil)

            Label(
                "Click any monitor in the diagram to edit that display.",
                systemImage: "cursorarrow.click"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        } else {
            InspectorHeader(
                title: "Select a Display",
                subtitle: "Choose a monitor in the diagram to configure it.",
                systemImage: "display.2"
            )
        }
    }

    private func sharedInspector(mode: SharedPresentationMode) -> some View {
        let wallpaper = model.wallpaper(id: model.state.sharedWallpaperID)

        return Group {
            InspectorHeader(
                title: mode == .duplicate ? "Duplicate" : "Span",
                subtitle: mode.inspectorDescription,
                systemImage: mode == .duplicate
                    ? "rectangle.on.rectangle"
                    : "rectangle.inset.filled"
            )

            WallpaperPreview(
                wallpaper: wallpaper,
                mode: mode == .duplicate ? .duplicate : .span
            )
            .frame(height: 176)

            InspectorField(title: "Shared Wallpaper") {
                WallpaperPicker(
                    selection: Binding(
                        get: { model.state.sharedWallpaperID },
                        set: { model.setSharedWallpaper($0) }
                    ),
                    wallpapers: model.assignableWallpapers,
                    includesNone: true
                )
            }

            InspectorField(title: "Scaling") {
                ScalingModePicker(
                    selection: Binding(
                        get: { model.state.settings.defaultScalingMode },
                        set: { model.setDefaultScalingMode($0) }
                    )
                )
            }

            Text(model.state.settings.defaultScalingMode.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Label(mode.behaviorSummary, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    private var modeTitle: String {
        switch model.state.settings.presentationMode {
        case .perDisplay: return "Independent displays"
        case .duplicate: return "One complete copy per display"
        case .span: return "One continuous canvas"
        }
    }

    private var modeIcon: String {
        switch model.state.settings.presentationMode {
        case .perDisplay: return "rectangle.split.2x1"
        case .duplicate: return "rectangle.on.rectangle"
        case .span: return "rectangle.inset.filled"
        }
    }

    private var modeDescription: String {
        switch model.state.settings.presentationMode {
        case .perDisplay:
            return "Each display stores its own wallpaper, enabled state, and scaling mode. Select a monitor to edit it in the inspector."
        case .duplicate:
            return "Every display shows the entire shared wallpaper. Each screen scales the same source independently, so crops can differ."
        case .span:
            return "Lumae treats the complete arrangement as one virtual desktop and gives each display its matching slice."
        }
    }

    private var modeExample: String {
        switch model.state.settings.presentationMode {
        case .perDisplay:
            return "Example: a video on the left monitor, an image on the right, and the laptop display disabled."
        case .duplicate:
            return "Example: the same full landscape appears separately on all three displays."
        case .span:
            return "Example: one panoramic image continues from the left monitor across the others."
        }
    }

    private func displaySummary(_ display: DisplayDescriptor) -> String {
        var parts = [
            "\(Int(display.pixelSize.width)) × \(Int(display.pixelSize.height))",
            String(format: "%.1f×", display.backingScaleFactor)
        ]
        if display.isMain { parts.append("Main") }
        if display.isBuiltIn { parts.append("Built-in") }
        return parts.joined(separator: " • ")
    }

    private func selectInitialDisplayIfNeeded() {
        let activeIDs = model.displayTopology.activeDisplayIDs
        if let selectedDisplayID = model.selectedDisplayID,
           activeIDs.contains(selectedDisplayID) {
            return
        }

        model.selectedDisplayID = model.displayTopology.displays
            .first(where: { $0.isMain })?.id
            ?? model.displayTopology.displays.first?.id
    }
}

private struct DisplayTopologyCanvas: View {
    let topology: DisplayTopology
    @Binding var selectedDisplayID: String?
    let assignments: [String: DisplayAssignment]
    let wallpapers: [UUID: WallpaperMetadata]
    let presentationMode: DisplayPresentationMode

    var body: some View {
        GeometryReader { proxy in
            let bounds = topology.virtualBoundsPoints
                ?? LRect(x: 0, y: 0, width: 1, height: 1)
            let padding = 32.0
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
                    let width = max(display.framePoints.size.width * scale, 120)
                    let height = max(display.framePoints.size.height * scale, 80)
                    let originX = offsetX
                        + (display.framePoints.minX - bounds.minX) * scale
                    let originY = offsetY
                        + (bounds.maxY - display.framePoints.maxY) * scale
                    let assignment = assignments[display.id]
                    let wallpaper = assignment?.wallpaperID.flatMap { wallpapers[$0] }
                    let selected = selectedDisplayID == display.id

                    Button {
                        selectedDisplayID = display.id
                    } label: {
                        DisplayPreviewCard(
                            display: display,
                            assignment: assignment,
                            wallpaper: wallpaper,
                            selected: selected,
                            presentationMode: presentationMode
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: width, height: height)
                    .position(
                        x: originX + width / 2,
                        y: originY + height / 2
                    )
                    .zIndex(selected ? 10 : (display.isMain ? 2 : 1))
                    .help("Select \(display.fingerprint.localizedName)")
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
    let presentationMode: DisplayPresentationMode

    var body: some View {
        ZStack {
            previewBackground
            Color.black.opacity(wallpaper == nil ? 0.05 : 0.32)

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
                    Text(String(format: "%.1f×", display.backingScaleFactor))
                    if display.isMain {
                        Text("Main")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.22), in: Capsule())
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(modeBadge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.34), in: Capsule())
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    selected ? Color.accentColor : Color.accentColor.opacity(0.58),
                    lineWidth: selected ? 4 : 1.5
                )
        }
        .shadow(
            color: selected ? Color.accentColor.opacity(0.28) : .clear,
            radius: 9
        )
        .opacity(assignment?.enabled == false ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: selected)
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

    private var modeBadge: String {
        switch presentationMode {
        case .perDisplay: return "Independent"
        case .duplicate: return "Full copy"
        case .span: return "Canvas slice"
        }
    }

    private var accessibilityDescription: String {
        var value = "\(display.fingerprint.localizedName), \(Int(display.pixelSize.width)) by \(Int(display.pixelSize.height)) pixels"
        if let wallpaper {
            value += ", assigned \(wallpaper.name)"
        } else {
            value += ", no wallpaper assigned"
        }
        return value
    }
}

private struct InspectorHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct InspectorField<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private enum WallpaperPreviewMode {
    case single
    case duplicate
    case span
}

private enum SharedPresentationMode {
    case duplicate
    case span

    var inspectorDescription: String {
        switch self {
        case .duplicate:
            return "One complete copy on every connected display."
        case .span:
            return "One continuous wallpaper divided across the display arrangement."
        }
    }

    var behaviorSummary: String {
        switch self {
        case .duplicate:
            return "All displays share one synchronized source, but each screen performs its own scaling and crop."
        case .span:
            return "All displays share one synchronized source and each screen renders only its section of the virtual canvas."
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
                    systemImage: wallpaper.kind == .video
                        ? "play.rectangle"
                        : "photo"
                )
                .tag(Optional(wallpaper.id))
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity)
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
            .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            .background(
                Color.black.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 4)
            )
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

    var explanation: String {
        switch self {
        case .fill:
            return "Fills the available display area and may crop the wallpaper."
        case .fit:
            return "Shows the complete wallpaper and may leave black bars."
        case .stretch:
            return "Fills the area without preserving the wallpaper's aspect ratio."
        case .center:
            return "Keeps the wallpaper at its original pixel dimensions."
        }
    }
}

private extension View {
    func canvasCard() -> some View {
        self
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
