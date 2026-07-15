import AppKit
import SwiftUI
import LumaeCore

struct WidgetsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var previewPosition = NormalizedWidgetPosition()
    @State private var confirmRemoval = false
    @State private var isDragging = false
    @State private var verticalSnapGuide: Double?
    @State private var horizontalSnapGuide: Double?

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    modeControl
                    previewCard
                    footerNote
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
        .onAppear {
            selectInitialDisplayIfNeeded()
            syncPreviewPosition()
        }
        .onChange(of: model.selectedDisplayID) { _, _ in
            syncPreviewPosition()
        }
        .onChange(of: model.widgetDisplayMode) { _, _ in
            syncPreviewPosition()
        }
        .onChange(of: editableClock?.position) { _, _ in
            if !isDragging { syncPreviewPosition() }
        }
        .onChange(of: model.displayTopology) { _, _ in
            selectInitialDisplayIfNeeded()
        }
        .confirmationDialog(
            removeConfirmationTitle,
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Clock", role: .destructive) {
                if let clock = editableClock {
                    model.removeWidget(id: clock.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Widgets")
                .font(.largeTitle.bold())

            Text("Place lightweight information directly on top of your wallpaper.")
                .foregroundStyle(.secondary)
        }
    }

    private var modeControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Display Behavior")
                    .font(.headline)
                Spacer()
                Label("Applies immediately", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(
                "Display Behavior",
                selection: Binding(
                    get: { model.widgetDisplayMode },
                    set: { model.setWidgetDisplayMode($0) }
                )
            ) {
                Label("Mirror", systemImage: "rectangle.on.rectangle")
                    .tag(WidgetDisplayMode.mirrored)
                Label("Per Display", systemImage: "rectangle.split.2x1")
                    .tag(WidgetDisplayMode.perDisplay)
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

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Wallpaper Preview")
                    .font(.headline)

                Spacer()

                if !model.displayTopology.displays.isEmpty {
                    Picker(
                        "Display",
                        selection: Binding(
                            get: { selectedDisplay?.id ?? "" },
                            set: { model.selectedDisplayID = $0 }
                        )
                    ) {
                        ForEach(model.displayTopology.displays) { display in
                            Label(
                                display.fingerprint.localizedName,
                                systemImage: display.isBuiltIn
                                    ? "laptopcomputer"
                                    : "display"
                            )
                            .tag(display.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }

            GeometryReader { proxy in
                ZStack {
                    previewWallpaper

                    if let verticalSnapGuide {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 1)
                            .position(
                                x: proxy.size.width * verticalSnapGuide,
                                y: proxy.size.height / 2
                            )
                            .allowsHitTesting(false)
                    }

                    if let horizontalSnapGuide {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(height: 1)
                            .position(
                                x: proxy.size.width / 2,
                                y: proxy.size.height * horizontalSnapGuide
                            )
                            .allowsHitTesting(false)
                    }

                    if let clock = editableClock,
                       selectedDisplayWidgetsEnabled,
                       clock.isEnabled {
                        DigitalClockWidgetView(widget: previewWidget(clock))
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: selectionCornerRadius(clock.size),
                                    style: .continuous
                                )
                                .stroke(
                                    Color.accentColor.opacity(isDragging ? 0.95 : 0.55),
                                    style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                                )
                                .padding(-6)
                            }
                            .contentShape(Rectangle())
                            .position(
                                x: proxy.size.width * previewPosition.x,
                                y: proxy.size.height * previewPosition.y
                            )
                            .gesture(
                                DragGesture(
                                    minimumDistance: 1,
                                    coordinateSpace: .named("widgetPreview")
                                )
                                .onChanged { value in
                                    isDragging = true
                                    let result = snappedPosition(
                                        for: value.location,
                                        in: proxy.size
                                    )
                                    previewPosition = result.position
                                    verticalSnapGuide = result.verticalGuide
                                    horizontalSnapGuide = result.horizontalGuide
                                }
                                .onEnded { value in
                                    let result = snappedPosition(
                                        for: value.location,
                                        in: proxy.size
                                    )
                                    previewPosition = result.position
                                    isDragging = false
                                    verticalSnapGuide = nil
                                    horizontalSnapGuide = nil
                                    model.setWidgetPosition(
                                        result.position,
                                        id: clock.id
                                    )
                                }
                            )
                            .help("Drag to reposition the clock")
                    } else {
                        emptyPreviewState
                    }
                }
                .coordinateSpace(name: "widgetPreview")
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.09), lineWidth: 1)
                }
            }
            .aspectRatio(16 / 10, contentMode: .fit)
        }
        .padding(18)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    @ViewBuilder
    private var emptyPreviewState: some View {
        if !selectedDisplayWidgetsEnabled, editableClock != nil {
            VStack(spacing: 12) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Widgets Hidden on This Display")
                    .font(.title3.bold())
                Button("Show Widgets") {
                    if let id = selectedDisplay?.id {
                        model.setWidgetsEnabled(true, for: id)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        } else if let clock = editableClock, !clock.isEnabled {
            VStack(spacing: 12) {
                Image(systemName: "clock.badge.xmark")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Clock Hidden")
                    .font(.title3.bold())
                Button("Show Clock") {
                    model.setWidgetEnabled(true, id: clock.id)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        } else {
            VStack(spacing: 14) {
                Image(systemName: "clock.badge.plus")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No Clock on This Display")
                    .font(.title3.bold())
                Text(addClockDescription)
                    .foregroundStyle(.secondary)
                Button("Add Digital Clock") {
                    addClock()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.widgetDisplayMode == .perDisplay && selectedDisplay == nil)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var footerNote: some View {
        Label(footerText, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let display = selectedDisplay {
                    displayHeader(display)
                    displayCard(display)

                    if let clock = editableClock {
                        appearanceCard(clock)
                        timeCard(clock)
                        placementCard(clock)
                        removalCard
                    } else {
                        addWidgetCard
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No Display Selected")
                            .font(.title3.bold())
                        Text("Connect or select a display to edit its widget layout.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
    }

    private func displayHeader(_ display: DisplayDescriptor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(display.fingerprint.localizedName)
                    .font(.title3.bold())
                Text(model.widgetDisplayMode == .mirrored
                    ? "Mirrored widget layout"
                    : "Independent widget layout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayCard(_ display: DisplayDescriptor) -> some View {
        WidgetInspectorCard(title: "Display") {
            Toggle(
                "Show widgets on this display",
                isOn: Binding(
                    get: { model.widgetDisplayEnabled(for: display.id) },
                    set: { model.setWidgetsEnabled($0, for: display.id) }
                )
            )

            Text(model.widgetDisplayMode == .mirrored
                ? "This hides the shared clock only on this monitor."
                : "This hides this monitor’s independent widget layout.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func appearanceCard(_ clock: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Appearance") {
            Toggle(
                "Show clock",
                isOn: Binding(
                    get: { clock.isEnabled },
                    set: { model.setWidgetEnabled($0, id: clock.id) }
                )
            )

            Divider()

            Toggle(
                "Show background",
                isOn: Binding(
                    get: { clock.digitalClock.showsBackground },
                    set: { model.setClockShowsBackground($0, id: clock.id) }
                )
            )

            Divider()

            Picker(
                "Size",
                selection: Binding(
                    get: { clock.size },
                    set: { model.setWidgetSize($0, id: clock.id) }
                )
            ) {
                Text("Small").tag(DesktopWidgetSize.small)
                Text("Medium").tag(DesktopWidgetSize.medium)
                Text("Large").tag(DesktopWidgetSize.large)
            }
            .pickerStyle(.segmented)
        }
    }

    private func timeCard(_ clock: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Time") {
            Toggle(
                "24-hour time",
                isOn: Binding(
                    get: { clock.digitalClock.uses24HourTime },
                    set: { model.setClockUses24HourTime($0, id: clock.id) }
                )
            )

            Divider()

            Toggle(
                "Show seconds",
                isOn: Binding(
                    get: { clock.digitalClock.showsSeconds },
                    set: { model.setClockShowsSeconds($0, id: clock.id) }
                )
            )
        }
    }

    private func placementCard(_ clock: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Placement") {
            Text("Drag the clock in the preview to place it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Reset to Top Center") {
                let position = NormalizedWidgetPosition(x: 0.5, y: 0.18)
                previewPosition = position
                model.setWidgetPosition(position, id: clock.id)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var addWidgetCard: some View {
        WidgetInspectorCard(title: "Widget") {
            Text(addClockDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Add Digital Clock") {
                addClock()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
    }

    private var removalCard: some View {
        WidgetInspectorCard(title: "Widget") {
            Button(role: .destructive) {
                confirmRemoval = true
            } label: {
                Label("Remove Clock", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var previewWallpaper: some View {
        if let wallpaper = representativeWallpaper {
            WallpaperThumbnail(item: wallpaper, animate: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.36)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var selectedDisplay: DisplayDescriptor? {
        guard let id = model.selectedDisplayID else { return nil }
        return model.displayTopology.display(id: id)
    }

    private var selectedDisplayWidgetsEnabled: Bool {
        guard let id = selectedDisplay?.id else { return true }
        return model.widgetDisplayEnabled(for: id)
    }

    private var editableClock: DesktopWidget? {
        model.digitalClockWidget(for: selectedDisplay?.id)
    }

    private var representativeWallpaper: WallpaperMetadata? {
        guard let display = selectedDisplay else {
            return model.assignableWallpapers.first
        }

        if model.state.settings.presentationMode == .perDisplay {
            let assignment = model.displayAssignment(for: display)
            if let wallpaper = model.wallpaper(id: assignment.wallpaperID) {
                return wallpaper
            }
        } else if let wallpaper = model.wallpaper(id: model.state.sharedWallpaperID) {
            return wallpaper
        }

        return model.assignableWallpapers.first
    }

    private var modeDescription: String {
        switch model.widgetDisplayMode {
        case .mirrored:
            return "Edit one shared clock layout, then hide it on individual monitors when needed."
        case .perDisplay:
            return "Each monitor keeps its own clock, position, size, and time settings."
        }
    }

    private var footerText: String {
        switch model.widgetDisplayMode {
        case .mirrored:
            return "Mirror keeps one widget layout synchronized across displays while still allowing individual monitors to hide widgets."
        case .perDisplay:
            return "Per Display lets every monitor keep a different clock layout or no clock at all."
        }
    }

    private var addClockDescription: String {
        model.widgetDisplayMode == .mirrored
            ? "Add one clock that mirrors across enabled displays."
            : "Add a clock only to the selected display."
    }

    private var removeConfirmationTitle: String {
        model.widgetDisplayMode == .mirrored
            ? "Remove the shared clock?"
            : "Remove the clock from this display?"
    }

    private func previewWidget(_ clock: DesktopWidget) -> DesktopWidget {
        var copy = clock
        copy.position = previewPosition
        return copy
    }

    private func addClock() {
        let id = model.addDigitalClockWidget(for: selectedDisplay?.id)
        if let clock = model.digitalClockWidget(for: selectedDisplay?.id),
           clock.id == id {
            previewPosition = clock.position
        }
    }

    private func snappedPosition(
        for location: CGPoint,
        in size: CGSize
    ) -> WidgetSnapResult {
        let raw = NormalizedWidgetPosition(
            x: min(max(location.x / max(size.width, 1), 0.10), 0.90),
            y: min(max(location.y / max(size.height, 1), 0.12), 0.88)
        )
        return WidgetSnapEngine.snap(
            position: raw,
            canvasSize: LSize(
                width: Double(size.width),
                height: Double(size.height)
            )
        )
    }

    private func selectionCornerRadius(_ size: DesktopWidgetSize) -> CGFloat {
        switch size {
        case .small: return 14
        case .medium: return 18
        case .large: return 22
        }
    }

    private func syncPreviewPosition() {
        previewPosition = editableClock?.position ?? NormalizedWidgetPosition()
    }

    private func selectInitialDisplayIfNeeded() {
        let activeIDs = model.displayTopology.activeDisplayIDs
        if let id = model.selectedDisplayID, activeIDs.contains(id) { return }
        model.selectedDisplayID = model.displayTopology.displays
            .first(where: { $0.isMain })?.id
            ?? model.displayTopology.displays.first?.id
    }
}

private struct WidgetInspectorCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
