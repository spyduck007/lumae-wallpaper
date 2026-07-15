import AppKit
import SwiftUI
import LumaeCore

struct WidgetsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedWidgetID: UUID?
    @State private var previewPositions: [UUID: NormalizedWidgetPosition] = [:]
    @State private var confirmRemoval = false
    @State private var draggingWidgetID: UUID?
    @State private var resizingWidgetID: UUID?
    @State private var previewCustomScales: [UUID: Double] = [:]
    @State private var resizeStartScale: Double?
    @State private var resizeStartDistance: CGFloat?
    @State private var verticalSnapGuide: Double?
    @State private var horizontalSnapGuide: Double?

    private enum ResizeCorner {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }

        var xDirection: CGFloat {
            switch self {
            case .topLeading, .bottomLeading: return -1
            case .topTrailing, .bottomTrailing: return 1
            }
        }

        var yDirection: CGFloat {
            switch self {
            case .topLeading, .topTrailing: return -1
            case .bottomLeading, .bottomTrailing: return 1
            }
        }
    }

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
            syncEditorState()
        }
        .onChange(of: model.selectedDisplayID) { _, _ in
            syncEditorState()
        }
        .onChange(of: model.widgetDisplayMode) { _, _ in
            syncEditorState()
        }
        .onChange(of: editableWidgets) { _, _ in
            if draggingWidgetID == nil, resizingWidgetID == nil {
                syncEditorState()
            }
        }
        .onChange(of: model.displayTopology) { _, _ in
            selectInitialDisplayIfNeeded()
            syncEditorState()
        }
        .confirmationDialog(
            removeConfirmationTitle,
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Widget", role: .destructive) {
                if let selectedWidgetID {
                    model.removeWidget(id: selectedWidgetID)
                    self.selectedWidgetID = nil
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

            HStack(spacing: 0) {
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
                .fixedSize()

                Spacer(minLength: 0)
            }

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

                addWidgetMenu

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
                    snapGuides(in: proxy.size)

                    if selectedDisplayWidgetsEnabled {
                        ForEach(editableWidgets.filter(\.isEnabled)) { widget in
                            editorWidget(widget, in: proxy.size)
                        }
                    }

                    if editableWidgets.isEmpty || !selectedDisplayWidgetsEnabled {
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
            .aspectRatio(previewAspectRatio, contentMode: .fit)
        }
        .padding(18)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private func editorWidget(
        _ widget: DesktopWidget,
        in previewSize: CGSize
    ) -> some View {
        let scale = totalPreviewScale(for: widget, in: previewSize)
        let isSelected = selectedWidgetID == widget.id
        let showsResizeHandles = isSelected && widget.size == .custom

        return DesktopWidgetContentView(widget: previewWidget(widget))
            .overlay {
                if isSelected {
                    selectionBorder(
                        for: widget,
                        totalScale: scale
                    )
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsResizeHandles {
                    resizeHandle(
                        corner: .topLeading,
                        widget: widget,
                        totalScale: scale,
                        previewSize: previewSize
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsResizeHandles {
                    resizeHandle(
                        corner: .topTrailing,
                        widget: widget,
                        totalScale: scale,
                        previewSize: previewSize
                    )
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsResizeHandles {
                    resizeHandle(
                        corner: .bottomLeading,
                        widget: widget,
                        totalScale: scale,
                        previewSize: previewSize
                    )
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsResizeHandles {
                    resizeHandle(
                        corner: .bottomTrailing,
                        widget: widget,
                        totalScale: scale,
                        previewSize: previewSize
                    )
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(scale, anchor: .center)
            .position(
                x: previewSize.width * previewPosition(for: widget).x,
                y: previewSize.height * previewPosition(for: widget).y
            )
            .onTapGesture {
                selectedWidgetID = widget.id
            }
            .gesture(dragGesture(for: widget, in: previewSize))
    }

    private func selectionBorder(
        for widget: DesktopWidget,
        totalScale: CGFloat
    ) -> some View {
        let safeScale = max(totalScale, 0.01)
        return RoundedRectangle(
            cornerRadius: selectionCornerRadius(widget),
            style: .continuous
        )
        .stroke(
            Color.accentColor.opacity(
                draggingWidgetID == widget.id || resizingWidgetID == widget.id
                    ? 0.95
                    : 0.62
            ),
            style: StrokeStyle(
                lineWidth: 2 / safeScale,
                dash: [7 / safeScale, 5 / safeScale]
            )
        )
        .padding(-7 / safeScale)
    }

    private func resizeHandle(
        corner: ResizeCorner,
        widget: DesktopWidget,
        totalScale: CGFloat,
        previewSize: CGSize
    ) -> some View {
        let safeScale = max(totalScale, 0.01)
        let visibleDiameter = 12 / safeScale
        let hitTarget = 28 / safeScale
        let outwardOffset = hitTarget / 2

        return ZStack {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: visibleDiameter, height: visibleDiameter)
                .overlay {
                    Circle()
                        .stroke(
                            Color.accentColor,
                            lineWidth: 2 / safeScale
                        )
                }
        }
        .frame(width: hitTarget, height: hitTarget)
        .contentShape(Rectangle())
        .offset(
            x: corner.xDirection * outwardOffset,
            y: corner.yDirection * outwardOffset
        )
        .highPriorityGesture(
            resizeGesture(for: widget, in: previewSize)
        )
        .help("Drag to resize proportionally")
    }

    @ViewBuilder
    private func snapGuides(in size: CGSize) -> some View {
        if let verticalSnapGuide {
            Rectangle()
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: 1)
                .position(
                    x: size.width * verticalSnapGuide,
                    y: size.height / 2
                )
                .allowsHitTesting(false)
        }

        if let horizontalSnapGuide {
            Rectangle()
                .fill(Color.accentColor.opacity(0.85))
                .frame(height: 1)
                .position(
                    x: size.width / 2,
                    y: size.height * horizontalSnapGuide
                )
                .allowsHitTesting(false)
        }
    }

    private func dragGesture(
        for widget: DesktopWidget,
        in size: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 1,
            coordinateSpace: .named("widgetPreview")
        )
        .onChanged { value in
            guard resizingWidgetID == nil else { return }
            selectedWidgetID = widget.id
            draggingWidgetID = widget.id
            let result = snappedPosition(for: value.location, in: size)
            previewPositions[widget.id] = result.position
            verticalSnapGuide = result.verticalGuide
            horizontalSnapGuide = result.horizontalGuide
        }
        .onEnded { value in
            guard resizingWidgetID == nil else { return }
            let result = snappedPosition(for: value.location, in: size)
            previewPositions[widget.id] = result.position
            draggingWidgetID = nil
            verticalSnapGuide = nil
            horizontalSnapGuide = nil
            model.setWidgetPosition(result.position, id: widget.id)
        }
    }

    private func resizeGesture(
        for widget: DesktopWidget,
        in previewSize: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named("widgetPreview")
        )
        .onChanged { value in
            selectedWidgetID = widget.id
            resizingWidgetID = widget.id

            let center = CGPoint(
                x: previewSize.width * previewPosition(for: widget).x,
                y: previewSize.height * previewPosition(for: widget).y
            )
            let distance = max(
                hypot(
                    value.location.x - center.x,
                    value.location.y - center.y
                ),
                1
            )

            if resizeStartDistance == nil {
                resizeStartDistance = distance
                resizeStartScale = previewCustomScale(for: widget)
            }

            guard let startDistance = resizeStartDistance,
                  let startScale = resizeStartScale else {
                return
            }

            let ratio = Double(distance / startDistance)
            previewCustomScales[widget.id] = DesktopWidget.clampedCustomScale(
                startScale * ratio
            )
        }
        .onEnded { _ in
            let finalScale = previewCustomScale(for: widget)
            resizingWidgetID = nil
            resizeStartDistance = nil
            resizeStartScale = nil
            model.setWidgetCustomScale(finalScale, id: widget.id)
        }
    }

    @ViewBuilder
    private var emptyPreviewState: some View {
        if !selectedDisplayWidgetsEnabled, !editableWidgets.isEmpty {
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
        } else {
            VStack(spacing: 14) {
                Image(systemName: "square.stack.3d.up.badge.plus")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No Widgets Yet")
                    .font(.title3.bold())
                Text("Use Add Widget above to place your first widget.")
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var addWidgetMenu: some View {
        Menu {
            Button {
                addWidget(.digitalClock)
            } label: {
                Label("Digital Clock", systemImage: "clock")
            }
            .disabled(editableWidgets.contains { $0.kind == .digitalClock })

            Button {
                addWidget(.nowPlaying)
            } label: {
                Label("Now Playing", systemImage: "music.note")
            }
            .disabled(editableWidgets.contains { $0.kind == .nowPlaying })
        } label: {
            Label("Add Widget", systemImage: "plus")
        }
        .disabled(
            model.widgetDisplayMode == .perDisplay
                && selectedDisplay == nil
                || editableWidgets.count >= DesktopWidgetKind.allCases.count
        )
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
                    widgetListCard

                    if let selectedWidget {
                        widgetHeader(selectedWidget)
                        appearanceCard(selectedWidget)

                        if selectedWidget.kind == .digitalClock {
                            timeCard(selectedWidget)
                        }

                        placementCard(selectedWidget)
                        removalCard(selectedWidget)
                    } else {
                        selectionHintCard
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
        }
    }

    private var widgetListCard: some View {
        WidgetInspectorCard(title: "Widgets") {
            if editableWidgets.isEmpty {
                Text("No widgets on this display.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(editableWidgets) { widget in
                    Button {
                        selectedWidgetID = widget.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: widgetIcon(widget.kind))
                                .frame(width: 20)
                            Text(widgetName(widget.kind))
                            Spacer()
                            if !widget.isEnabled {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.secondary)
                            }
                            if selectedWidgetID == widget.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

        }
    }

    private func widgetHeader(_ widget: DesktopWidget) -> some View {
        HStack(spacing: 12) {
            Image(systemName: widgetIcon(widget.kind))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(widgetName(widget.kind))
                    .font(.title3.bold())
                Text(widgetSubtitle(widget.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func appearanceCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Appearance") {
            Toggle(
                "Show widget",
                isOn: Binding(
                    get: { widget.isEnabled },
                    set: { model.setWidgetEnabled($0, id: widget.id) }
                )
            )

            Divider()

            Toggle(
                "Show background",
                isOn: Binding(
                    get: { showsBackground(widget) },
                    set: { setShowsBackground($0, widget: widget) }
                )
            )

            Divider()

            Picker(
                "Size",
                selection: Binding(
                    get: { widget.size },
                    set: { model.setWidgetSize($0, id: widget.id) }
                )
            ) {
                Text("Small").tag(DesktopWidgetSize.small)
                Text("Medium").tag(DesktopWidgetSize.medium)
                Text("Large").tag(DesktopWidgetSize.large)
                Text("Custom").tag(DesktopWidgetSize.custom)
            }
            .pickerStyle(.segmented)

            if widget.size == .custom {
                Text("Drag any corner handle in the preview to resize proportionally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func timeCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Time") {
            Toggle(
                "24-hour time",
                isOn: Binding(
                    get: { widget.digitalClock.uses24HourTime },
                    set: { model.setClockUses24HourTime($0, id: widget.id) }
                )
            )

            Divider()

            Toggle(
                "Show seconds",
                isOn: Binding(
                    get: { widget.digitalClock.showsSeconds },
                    set: { model.setClockShowsSeconds($0, id: widget.id) }
                )
            )
        }
    }

    private func placementCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Placement") {
            Text("Drag the selected widget in the preview to place it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Reset Position") {
                let position = defaultPosition(widget.kind)
                previewPositions[widget.id] = position
                model.setWidgetPosition(position, id: widget.id)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var selectionHintCard: some View {
        WidgetInspectorCard(title: "Widget") {
            Text("Use Add Widget above, then select a widget in the preview or list to edit it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func removalCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Widget") {
            Button(role: .destructive) {
                selectedWidgetID = widget.id
                confirmRemoval = true
            } label: {
                Label("Remove \(widgetName(widget.kind))", systemImage: "trash")
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

    private var previewAspectRatio: CGFloat {
        guard let display = selectedDisplay,
              display.framePoints.size.height > 0 else {
            return 16 / 10
        }
        return CGFloat(
            display.framePoints.size.width / display.framePoints.size.height
        )
    }

    private func previewScale(in previewSize: CGSize) -> CGFloat {
        guard let display = selectedDisplay,
              display.framePoints.size.width > 0,
              display.framePoints.size.height > 0 else {
            return 1
        }

        let horizontalScale = previewSize.width
            / CGFloat(display.framePoints.size.width)
        let verticalScale = previewSize.height
            / CGFloat(display.framePoints.size.height)
        return max(min(horizontalScale, verticalScale), 0.01)
    }

    private var selectedDisplay: DisplayDescriptor? {
        guard let id = model.selectedDisplayID else { return nil }
        return model.displayTopology.display(id: id)
    }

    private var selectedDisplayWidgetsEnabled: Bool {
        guard let id = selectedDisplay?.id else { return true }
        return model.widgetDisplayEnabled(for: id)
    }

    private var editableWidgets: [DesktopWidget] {
        if model.widgetDisplayMode == .mirrored {
            return model.widgets
        }
        guard let id = selectedDisplay?.id else { return [] }
        return model.widgetsForDisplay(id)
    }

    private var selectedWidget: DesktopWidget? {
        guard let selectedWidgetID else { return nil }
        return editableWidgets.first { $0.id == selectedWidgetID }
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
        model.widgetDisplayMode == .mirrored
            ? "Edit one shared widget layout, then hide it on individual monitors when needed."
            : "Each monitor keeps its own widgets, positions, and appearance settings."
    }

    private var footerText: String {
        model.widgetDisplayMode == .mirrored
            ? "Mirror keeps one widget layout synchronized across displays while still allowing individual monitors to hide widgets."
            : "Per Display lets every monitor keep a different widget layout."
    }

    private var removeConfirmationTitle: String {
        guard let selectedWidget else { return "Remove widget?" }
        return model.widgetDisplayMode == .mirrored
            ? "Remove the shared \(widgetName(selectedWidget.kind))?"
            : "Remove \(widgetName(selectedWidget.kind)) from this display?"
    }

    private func addWidget(_ kind: DesktopWidgetKind) {
        let id = model.addWidget(kind: kind, for: selectedDisplay?.id)
        selectedWidgetID = id
        if let widget = model.widget(id: id, for: selectedDisplay?.id) {
            previewPositions[id] = widget.position
        }
    }

    private func previewWidget(_ widget: DesktopWidget) -> DesktopWidget {
        var copy = widget
        copy.position = previewPosition(for: widget)
        if copy.size == .custom {
            copy.customScale = previewCustomScale(for: widget)
        }
        return copy
    }

    private func previewCustomScale(for widget: DesktopWidget) -> Double {
        previewCustomScales[widget.id] ?? widget.renderingScale
    }

    private func totalPreviewScale(
        for widget: DesktopWidget,
        in previewSize: CGSize
    ) -> CGFloat {
        previewScale(in: previewSize)
            * CGFloat(widget.size == .custom ? previewCustomScale(for: widget) : 1)
    }

    private func previewPosition(for widget: DesktopWidget) -> NormalizedWidgetPosition {
        previewPositions[widget.id] ?? widget.position
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

    private func selectionCornerRadius(_ widget: DesktopWidget) -> CGFloat {
        switch widget.kind {
        case .digitalClock:
            switch widget.size {
            case .small: return 16
            case .medium, .custom: return 20
            case .large: return 25
            }
        case .nowPlaying:
            switch widget.size {
            case .small: return 16
            case .medium, .custom: return 21
            case .large: return 27
            }
        }
    }

    private func syncEditorState() {
        previewPositions = Dictionary(
            uniqueKeysWithValues: editableWidgets.map { ($0.id, $0.position) }
        )
        previewCustomScales = Dictionary(
            uniqueKeysWithValues: editableWidgets.map {
                ($0.id, $0.renderingScale)
            }
        )
        if let selectedWidgetID,
           editableWidgets.contains(where: { $0.id == selectedWidgetID }) {
            return
        }
        selectedWidgetID = editableWidgets.first?.id
    }

    private func selectInitialDisplayIfNeeded() {
        let activeIDs = model.displayTopology.activeDisplayIDs
        if let id = model.selectedDisplayID, activeIDs.contains(id) { return }
        model.selectedDisplayID = model.displayTopology.displays
            .first(where: { $0.isMain })?.id
            ?? model.displayTopology.displays.first?.id
    }

    private func showsBackground(_ widget: DesktopWidget) -> Bool {
        switch widget.kind {
        case .digitalClock: return widget.digitalClock.showsBackground
        case .nowPlaying: return widget.nowPlaying.showsBackground
        }
    }

    private func setShowsBackground(_ enabled: Bool, widget: DesktopWidget) {
        switch widget.kind {
        case .digitalClock:
            model.setClockShowsBackground(enabled, id: widget.id)
        case .nowPlaying:
            model.setNowPlayingShowsBackground(enabled, id: widget.id)
        }
    }

    private func defaultPosition(_ kind: DesktopWidgetKind) -> NormalizedWidgetPosition {
        switch kind {
        case .digitalClock: return NormalizedWidgetPosition(x: 0.5, y: 0.18)
        case .nowPlaying: return NormalizedWidgetPosition(x: 0.5, y: 0.78)
        }
    }

    private func widgetName(_ kind: DesktopWidgetKind) -> String {
        switch kind {
        case .digitalClock: return "Digital Clock"
        case .nowPlaying: return "Now Playing"
        }
    }

    private func widgetIcon(_ kind: DesktopWidgetKind) -> String {
        switch kind {
        case .digitalClock: return "clock"
        case .nowPlaying: return "music.note"
        }
    }

    private func widgetSubtitle(_ kind: DesktopWidgetKind) -> String {
        switch kind {
        case .digitalClock: return "A clean, glanceable time display"
        case .nowPlaying: return "Artwork, progress, and playback activity"
        }
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
