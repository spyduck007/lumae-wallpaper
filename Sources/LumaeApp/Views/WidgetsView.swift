import AppKit
import SwiftUI
import LumaeCore

struct WidgetsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedWidgetID: UUID?
    @State private var pendingRemovalID: UUID?
    @State private var previewPositions: [UUID: NormalizedWidgetPosition] = [:]
    @State private var previewCustomScales: [UUID: Double] = [:]
    @State private var measuredWidgetSizes: [UUID: CGSize] = [:]
    @State private var previewCanvasSize: CGSize = .zero
    @State private var draggingWidgetID: UUID?
    @State private var resizingWidgetID: UUID?
    @State private var dragStartPosition: NormalizedWidgetPosition?
    @State private var resizeStartScale: Double?
    @State private var resizeStartDistance: CGFloat?
    @State private var verticalSnapGuides: [CGFloat] = []
    @State private var horizontalSnapGuides: [CGFloat] = []
    @State private var equalHorizontalSpacing = false
    @State private var equalVerticalSpacing = false
    @State private var showsWidgetChooser = false

    private enum ResizeCorner: CaseIterable, Hashable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing

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
                    defaultAppearanceControl
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
        .background {
            WidgetKeyboardMonitor { event in
                handleKeyboardEvent(event)
            }
        }
        .onAppear {
            selectInitialDisplayIfNeeded()
            syncEditorState()
        }
        .onChange(of: model.selectedDisplayID) { _, _ in syncEditorState() }
        .onChange(of: model.widgetDisplayMode) { _, _ in syncEditorState() }
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
            removalConfirmationTitle,
            isPresented: Binding(
                get: { pendingRemovalID != nil },
                set: { if !$0 { pendingRemovalID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Widget", role: .destructive) {
                guard let id = pendingRemovalID else { return }
                model.removeWidget(id: id, for: selectedDisplay?.id)
                if selectedWidgetID == id { selectedWidgetID = nil }
                pendingRemovalID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemovalID = nil
            }
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
        }
    }

    private var defaultAppearanceControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Default Widget Style")
                        .font(.headline)
                    Text("New widgets use this style unless you change them individually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Apply to All Widgets") {
                    model.applyDefaultStyleToAllWidgets()
                }
                .disabled(model.widgets.isEmpty && model.widgetDisplayConfigurations.allSatisfy { $0.widgets.isEmpty })
            }

            HStack(spacing: 0) {
                Picker(
                    "Default Widget Style",
                    selection: Binding(
                        get: { model.defaultWidgetStyle },
                        set: { model.setDefaultWidgetStyle($0) }
                    )
                ) {
                    Text("Glass").tag(WidgetVisualStyle.glass)
                    Text("Clear").tag(WidgetVisualStyle.clear)
                    Text("Contrast").tag(WidgetVisualStyle.highContrast)
                    Text("None").tag(WidgetVisualStyle.none)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
            }
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedWidgetID = nil
                        }

                    snapGuides(in: proxy.size)

                    if selectedDisplayWidgetsEnabled {
                        ForEach(editableWidgets.filter(\.isEnabled)) { widget in
                            editorWidget(widget, in: proxy.size)
                        }

                        if let widget = selectedWidget,
                           widget.size == .custom,
                           widget.isEnabled,
                           let measured = measuredWidgetSizes[widget.id] {
                            resizeControls(
                                for: widget,
                                measuredSize: measured,
                                previewSize: proxy.size
                            )
                        }
                    }

                    if editableWidgets.isEmpty || !selectedDisplayWidgetsEnabled {
                        emptyPreviewState
                    }

                    if equalHorizontalSpacing || equalVerticalSpacing {
                        Text("Equal spacing")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 12)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "widgetPreview")
                .onAppear { previewCanvasSize = proxy.size }
                .onChange(of: proxy.size) { _, size in previewCanvasSize = size }
                .onPreferenceChange(WidgetMeasuredSizePreferenceKey.self) { sizes in
                    measuredWidgetSizes.merge(sizes) { _, new in new }
                    normalizeWidgetBounds(in: proxy.size)
                }
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
        let scale = previewScale(in: previewSize)
        let selected = selectedWidgetID == widget.id

        return DesktopWidgetContentView(widget: previewWidget(widget))
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: WidgetMeasuredSizePreferenceKey.self,
                        value: [widget.id: geometry.size]
                    )
                }
            }
            .overlay {
                if selected {
                    RoundedRectangle(
                        cornerRadius: selectionCornerRadius(widget),
                        style: .continuous
                    )
                    .stroke(
                        Color.accentColor.opacity(
                            draggingWidgetID == widget.id || resizingWidgetID == widget.id
                                ? 0.95
                                : 0.70
                        ),
                        lineWidth: 1.5 / max(scale, 0.01)
                    )
                    .padding(-6 / max(scale, 0.01))
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(scale, anchor: .center)
            .position(
                x: previewSize.width * previewPosition(for: widget).x,
                y: previewSize.height * previewPosition(for: widget).y
            )
            .onHover { hovering in
                if hovering, resizingWidgetID == nil {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .onTapGesture {
                selectedWidgetID = widget.id
            }
            .gesture(dragGesture(for: widget, in: previewSize))
            .contextMenu {
                widgetContextMenu(widget)
            }
    }

    @ViewBuilder
    private func snapGuides(in size: CGSize) -> some View {
        ForEach(verticalSnapGuides.indices, id: \.self) { index in
            Rectangle()
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: 1)
                .position(x: verticalSnapGuides[index], y: size.height / 2)
                .allowsHitTesting(false)
        }
        ForEach(horizontalSnapGuides.indices, id: \.self) { index in
            Rectangle()
                .fill(Color.accentColor.opacity(0.85))
                .frame(height: 1)
                .position(x: size.width / 2, y: horizontalSnapGuides[index])
                .allowsHitTesting(false)
        }
    }

    private func dragGesture(
        for widget: DesktopWidget,
        in previewSize: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 1,
            coordinateSpace: .named("widgetPreview")
        )
        .onChanged { value in
            guard resizingWidgetID == nil else { return }
            selectedWidgetID = widget.id
            draggingWidgetID = widget.id
            if dragStartPosition == nil {
                dragStartPosition = previewPosition(for: widget)
                NSCursor.closedHand.set()
            }
            guard let start = dragStartPosition else { return }
            let desired = CGPoint(
                x: previewSize.width * start.x + value.translation.width,
                y: previewSize.height * start.y + value.translation.height
            )
            let result = canvasSnapResult(
                for: widget,
                desiredCenter: desired,
                previewSize: previewSize
            )
            previewPositions[widget.id] = normalizedCenter(
                of: result.frame,
                in: previewSize
            )
            applyGuides(result)
        }
        .onEnded { _ in
            guard resizingWidgetID == nil else { return }
            dragStartPosition = nil
            draggingWidgetID = nil
            NSCursor.arrow.set()
            clearGuides()
            model.setWidgetPosition(previewPosition(for: widget), id: widget.id)
        }
    }

    @ViewBuilder
    private func resizeControls(
        for widget: DesktopWidget,
        measuredSize: CGSize,
        previewSize: CGSize
    ) -> some View {
        let scale = previewScale(in: previewSize)
        let rendered = CGSize(
            width: measuredSize.width * scale,
            height: measuredSize.height * scale
        )
        let center = CGPoint(
            x: previewSize.width * previewPosition(for: widget).x,
            y: previewSize.height * previewPosition(for: widget).y
        )

        ForEach(Array(ResizeCorner.allCases), id: \.self) { corner in
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 12, height: 12)
                .overlay { Circle().stroke(Color.accentColor, lineWidth: 2) }
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .position(
                    x: center.x + corner.xDirection * rendered.width / 2,
                    y: center.y + corner.yDirection * rendered.height / 2
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.crosshair.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .highPriorityGesture(
                    resizeGesture(for: widget, in: previewSize)
                )
                .help("Drag to resize proportionally")
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
            let distance = max(hypot(value.location.x - center.x, value.location.y - center.y), 1)
            if resizeStartDistance == nil {
                resizeStartDistance = distance
                resizeStartScale = previewCustomScale(for: widget)
            }
            guard let startDistance = resizeStartDistance,
                  let startScale = resizeStartScale else { return }

            let proposed = DesktopWidget.clampedCustomScale(
                startScale * Double(distance / startDistance)
            )
            let currentFrame = previewFrame(for: widget, in: previewSize)
            let maximum = WidgetCanvasEngine.maximumScale(
                currentFrame: lRect(currentFrame),
                currentScale: previewCustomScale(for: widget),
                center: LPoint(x: Double(center.x), y: Double(center.y)),
                canvasSize: LSize(
                    width: Double(previewSize.width),
                    height: Double(previewSize.height)
                )
            )
            previewCustomScales[widget.id] = min(proposed, maximum)
        }
        .onEnded { _ in
            let final = previewCustomScale(for: widget)
            resizingWidgetID = nil
            resizeStartDistance = nil
            resizeStartScale = nil
            model.setWidgetCustomScale(final, id: widget.id)
        }
    }

    private var addWidgetMenu: some View {
        Button {
            showsWidgetChooser.toggle()
        } label: {
            Label("Add Widget", systemImage: "plus")
        }
        .disabled(model.widgetDisplayMode == .perDisplay && selectedDisplay == nil)
        .popover(
            isPresented: $showsWidgetChooser,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            WidgetChooserView { kind in
                addWidget(kind)
                showsWidgetChooser = false
            }
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
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.badge.plus")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No Widgets Yet")
                    .font(.title3.bold())
                Text("Use Add Widget above to place your first widget.")
                    .foregroundStyle(.secondary)
            }
            .padding(26)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var footerNote: some View {
        Label(footerText, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let display = selectedDisplay {
                    displayHeader(display)
                    displayCard(display)
                    widgetListCard

                    if let widget = selectedWidget {
                        widgetHeader(widget)
                        appearanceCard(widget)
                        switch widget.kind {
                        case .digitalClock:
                            timeCard(widget)
                        case .dateCalendar:
                            dateCalendarCard(widget)
                        case .battery:
                            batteryCard(widget)
                        case .weather:
                            weatherCard(widget)
                        case .nowPlaying:
                            EmptyView()
                        }
                        placementCard(widget)
                        actionsCard(widget)
                    } else {
                        WidgetInspectorCard(title: "Widget") {
                            Text("Select a widget in the preview or list to edit it.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Display Selected",
                        systemImage: "display.trianglebadge.exclamationmark",
                        description: Text("Connect or select a display to edit widgets.")
                    )
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
                            Text(widgetDisplayName(widget))
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
                    .contextMenu { widgetContextMenu(widget) }
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
                Text(widgetDisplayName(widget))
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
            VStack(alignment: .leading, spacing: 7) {
                Text("Style")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "Style",
                    selection: Binding(
                        get: { widget.style },
                        set: { model.setWidgetStyle($0, id: widget.id) }
                    )
                ) {
                    Text("Glass").tag(WidgetVisualStyle.glass)
                    Text("Clear").tag(WidgetVisualStyle.clear)
                    Text("Contrast").tag(WidgetVisualStyle.highContrast)
                    Text("None").tag(WidgetVisualStyle.none)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            if widget.kind == .nowPlaying,
               widget.style != .none {
                Toggle(
                    "Use artwork tint",
                    isOn: Binding(
                        get: { widget.nowPlaying.usesArtworkTint },
                        set: { model.setNowPlayingUsesArtworkTint($0, id: widget.id) }
                    )
                )
            }

            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("Size")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "Size",
                    selection: Binding(
                        get: { widget.size },
                        set: { size in
                            model.setWidgetSize(size, id: widget.id)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                constrainWidgetToCanvas(widget.id)
                            }
                        }
                    )
                ) {
                    Text("Small").tag(DesktopWidgetSize.small)
                    Text("Medium").tag(DesktopWidgetSize.medium)
                    Text("Large").tag(DesktopWidgetSize.large)
                    Text("Custom").tag(DesktopWidgetSize.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            if widget.size == .custom {
                Text("Drag a corner handle to resize proportionally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func dateCalendarCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Date & Calendar") {
            Picker(
                "Layout",
                selection: Binding(
                    get: { widget.dateCalendar.mode },
                    set: { model.setDateCalendarMode($0, id: widget.id) }
                )
            ) {
                Text("Compact").tag(DateCalendarWidgetMode.compactDate)
                Text("Full").tag(DateCalendarWidgetMode.fullDate)
                Text("Month").tag(DateCalendarWidgetMode.monthCalendar)
            }
            .pickerStyle(.segmented)

            Divider()

            if widget.dateCalendar.mode == .monthCalendar {
                Picker(
                    "Week starts",
                    selection: Binding(
                        get: { widget.dateCalendar.weekStart },
                        set: { model.setCalendarWeekStart($0, id: widget.id) }
                    )
                ) {
                    Text("System").tag(CalendarWeekStart.system)
                    Text("Sunday").tag(CalendarWeekStart.sunday)
                    Text("Monday").tag(CalendarWeekStart.monday)
                }

                Toggle(
                    "Show adjacent-month dates",
                    isOn: Binding(
                        get: { widget.dateCalendar.showsAdjacentMonthDates },
                        set: { model.setCalendarShowsAdjacentDates($0, id: widget.id) }
                    )
                )
            } else {
                Toggle(
                    "Show weekday",
                    isOn: Binding(
                        get: { widget.dateCalendar.showsWeekday },
                        set: { model.setDateShowsWeekday($0, id: widget.id) }
                    )
                )
            }

            Toggle(
                "Show year",
                isOn: Binding(
                    get: { widget.dateCalendar.showsYear },
                    set: { model.setDateShowsYear($0, id: widget.id) }
                )
            )
        }
    }

    private func batteryCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Battery") {
            Toggle(
                "Show percentage",
                isOn: Binding(
                    get: { widget.battery.showsPercentage },
                    set: { model.setBatteryShowsPercentage($0, id: widget.id) }
                )
            )
            Toggle(
                "Show status text",
                isOn: Binding(
                    get: { widget.battery.showsStatusText },
                    set: { model.setBatteryShowsStatusText($0, id: widget.id) }
                )
            )
            Toggle(
                "Show progress bar",
                isOn: Binding(
                    get: { widget.battery.showsProgressBar },
                    set: { model.setBatteryShowsProgressBar($0, id: widget.id) }
                )
            )
        }
    }

    private func weatherCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Weather") {
            if !model.state.settings.weatherEnabled {
                Label(
                    "Weather is off. Turn it on in Settings to allow a location-based network request.",
                    systemImage: "network.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
            }

            Picker(
                "Layout",
                selection: Binding(
                    get: { widget.weather.mode },
                    set: { model.setWeatherMode($0, id: widget.id) }
                )
            ) {
                Text("Current").tag(WeatherWidgetMode.current)
                Text("Forecast").tag(WeatherWidgetMode.forecast)
            }
            .pickerStyle(.segmented)

            if widget.weather.mode == .forecast {
                Text("Shows today plus the next five days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Picker(
                "Temperature unit",
                selection: Binding(
                    get: { widget.weather.temperatureUnit },
                    set: { model.setWeatherTemperatureUnit($0, id: widget.id) }
                )
            ) {
                Text("°F").tag(WeatherTemperatureUnit.fahrenheit)
                Text("°C").tag(WeatherTemperatureUnit.celsius)
            }
            .pickerStyle(.segmented)

            Divider()

            Toggle(
                "Show condition",
                isOn: Binding(
                    get: { widget.weather.showsCondition },
                    set: { model.setWeatherShowsCondition($0, id: widget.id) }
                )
            )
            Toggle(
                "Show high/low",
                isOn: Binding(
                    get: { widget.weather.showsHighLow },
                    set: { model.setWeatherShowsHighLow($0, id: widget.id) }
                )
            )
            Toggle(
                "Show location name",
                isOn: Binding(
                    get: { widget.weather.showsLocationName },
                    set: { model.setWeatherShowsLocationName($0, id: widget.id) }
                )
            )
        }
    }

    private func placementCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Placement") {
            Text("Drag to move. Arrow keys nudge; Shift makes a larger step.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Reset Position") {
                let position = defaultPosition(widget.kind)
                previewPositions[widget.id] = position
                model.setWidgetPosition(position, id: widget.id)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func actionsCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Widget") {
            Button {
                duplicateSelectedWidget(widget)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            Button(role: .destructive) {
                pendingRemovalID = widget.id
            } label: {
                Label("Remove", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func widgetContextMenu(_ widget: DesktopWidget) -> some View {
        Button("Duplicate") { duplicateSelectedWidget(widget) }
        Divider()
        Button("Bring Forward") {
            model.bringWidgetForward(id: widget.id, for: selectedDisplay?.id)
        }
        Button("Send Backward") {
            model.sendWidgetBackward(id: widget.id, for: selectedDisplay?.id)
        }
        Button("Bring to Front") {
            model.bringWidgetToFront(id: widget.id, for: selectedDisplay?.id)
        }
        Button("Send to Back") {
            model.sendWidgetToBack(id: widget.id, for: selectedDisplay?.id)
        }
        Divider()
        Button("Remove", role: .destructive) {
            pendingRemovalID = widget.id
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

    private var editableWidgets: [DesktopWidget] {
        model.widgetDisplayMode == .mirrored
            ? model.widgets
            : selectedDisplay.map { model.widgetLayoutForEditing($0.id) } ?? []
    }

    private var selectedWidget: DesktopWidget? {
        guard let selectedWidgetID else { return nil }
        return editableWidgets.first { $0.id == selectedWidgetID }
    }

    private var previewAspectRatio: CGFloat {
        guard let display = selectedDisplay,
              display.framePoints.size.height > 0 else { return 16 / 10 }
        return CGFloat(display.framePoints.size.width / display.framePoints.size.height)
    }

    private func previewScale(in size: CGSize) -> CGFloat {
        guard let display = selectedDisplay,
              display.framePoints.size.width > 0,
              display.framePoints.size.height > 0 else { return 1 }
        return max(min(
            size.width / CGFloat(display.framePoints.size.width),
            size.height / CGFloat(display.framePoints.size.height)
        ), 0.01)
    }

    private var representativeWallpaper: WallpaperMetadata? {
        guard let display = selectedDisplay else { return model.assignableWallpapers.first }
        if model.state.settings.presentationMode == .perDisplay {
            return model.wallpaper(id: model.displayAssignment(for: display).wallpaperID)
        }
        return model.wallpaper(id: model.state.sharedWallpaperID)
            ?? model.assignableWallpapers.first
    }

    private func previewWidget(_ widget: DesktopWidget) -> DesktopWidget {
        var copy = widget
        copy.position = previewPosition(for: widget)
        if copy.size == .custom {
            copy.customScale = previewCustomScale(for: widget)
        }
        return copy
    }

    private func previewPosition(for widget: DesktopWidget) -> NormalizedWidgetPosition {
        previewPositions[widget.id] ?? widget.position
    }

    private func previewCustomScale(for widget: DesktopWidget) -> Double {
        previewCustomScales[widget.id] ?? widget.renderingScale
    }

    private func previewFrame(for widget: DesktopWidget, in size: CGSize) -> CGRect {
        let measured = measuredWidgetSizes[widget.id] ?? CGSize(width: 180, height: 90)
        let scale = previewScale(in: size)
        let rendered = CGSize(width: measured.width * scale, height: measured.height * scale)
        let center = CGPoint(
            x: size.width * previewPosition(for: widget).x,
            y: size.height * previewPosition(for: widget).y
        )
        return CGRect(
            x: center.x - rendered.width / 2,
            y: center.y - rendered.height / 2,
            width: rendered.width,
            height: rendered.height
        )
    }

    private func canvasSnapResult(
        for widget: DesktopWidget,
        desiredCenter: CGPoint,
        previewSize: CGSize
    ) -> WidgetCanvasSnapResult {
        var movingFrame = previewFrame(for: widget, in: previewSize)
        movingFrame.origin = CGPoint(
            x: desiredCenter.x - movingFrame.width / 2,
            y: desiredCenter.y - movingFrame.height / 2
        )
        let moving = WidgetCanvasItem(id: widget.id, frame: lRect(movingFrame))
        let others = editableWidgets
            .filter { $0.id != widget.id && $0.isEnabled }
            .map { WidgetCanvasItem(id: $0.id, frame: lRect(previewFrame(for: $0, in: previewSize))) }
        return WidgetCanvasEngine.snap(
            moving: moving,
            canvasSize: LSize(
                width: Double(previewSize.width),
                height: Double(previewSize.height)
            ),
            others: others
        )
    }

    private func normalizedCenter(
        of frame: LRect,
        in size: CGSize
    ) -> NormalizedWidgetPosition {
        NormalizedWidgetPosition(
            x: frame.midX / Double(max(size.width, 1)),
            y: frame.midY / Double(max(size.height, 1))
        )
    }

    private func applyGuides(_ result: WidgetCanvasSnapResult) {
        verticalSnapGuides = result.verticalGuides.map { value in
            CGFloat(value)
        }
        horizontalSnapGuides = result.horizontalGuides.map { value in
            CGFloat(value)
        }
        equalHorizontalSpacing = result.hasEqualHorizontalSpacing
        equalVerticalSpacing = result.hasEqualVerticalSpacing
    }

    private func clearGuides() {
        verticalSnapGuides = []
        horizontalSnapGuides = []
        equalHorizontalSpacing = false
        equalVerticalSpacing = false
    }

    private func lRect(_ rect: CGRect) -> LRect {
        LRect(
            x: Double(rect.minX),
            y: Double(rect.minY),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    private func normalizeWidgetBounds(in canvasSize: CGSize) {
        guard draggingWidgetID == nil,
              resizingWidgetID == nil,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return
        }
        for widget in editableWidgets where widget.isEnabled {
            let frame = previewFrame(for: widget, in: canvasSize)
            let bounded = WidgetCanvasEngine.clamp(
                lRect(frame),
                to: LSize(
                    width: Double(canvasSize.width),
                    height: Double(canvasSize.height)
                )
            )
            guard bounded != lRect(frame) else { continue }
            let position = normalizedCenter(of: bounded, in: canvasSize)
            previewPositions[widget.id] = position
            model.normalizeWidgetPosition(position, id: widget.id)
        }
    }

    private func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "z" {
                if event.modifierFlags.contains(.shift) {
                    model.redoWidgetEdit()
                } else {
                    model.undoWidgetEdit()
                }
                return true
            }
            if key == "d", let widget = selectedWidget {
                duplicateSelectedWidget(widget)
                return true
            }
            return false
        }

        switch event.keyCode {
        case 53:
            selectedWidgetID = nil
            return true
        case 51, 117:
            if let selectedWidgetID {
                pendingRemovalID = selectedWidgetID
                return true
            }
        case 123, 124, 125, 126:
            return nudgeSelectedWidget(
                keyCode: event.keyCode,
                largeStep: event.modifierFlags.contains(.shift)
            )
        default:
            break
        }
        return false
    }

    private func constrainWidgetToCanvas(_ id: UUID) {
        guard previewCanvasSize.width > 0,
              let widget = editableWidgets.first(where: { $0.id == id }) else {
            return
        }
        let frame = previewFrame(for: widget, in: previewCanvasSize)
        let bounded = WidgetCanvasEngine.clamp(
            lRect(frame),
            to: LSize(
                width: Double(previewCanvasSize.width),
                height: Double(previewCanvasSize.height)
            )
        )
        guard bounded != lRect(frame) else { return }
        let position = normalizedCenter(of: bounded, in: previewCanvasSize)
        previewPositions[id] = position
        model.setWidgetPosition(position, id: id)
    }

    private func nudgeSelectedWidget(
        keyCode: UInt16,
        largeStep: Bool
    ) -> Bool {
        guard let widget = selectedWidget, previewCanvasSize.width > 0 else { return false }
        let step: CGFloat = largeStep ? 10 : 1
        var frame = previewFrame(for: widget, in: previewCanvasSize)
        switch keyCode {
        case 123: frame.origin.x -= step
        case 124: frame.origin.x += step
        case 125: frame.origin.y += step
        case 126: frame.origin.y -= step
        default: return false
        }
        let bounded = WidgetCanvasEngine.clamp(
            lRect(frame),
            to: LSize(
                width: Double(previewCanvasSize.width),
                height: Double(previewCanvasSize.height)
            )
        )
        let position = normalizedCenter(of: bounded, in: previewCanvasSize)
        previewPositions[widget.id] = position
        model.setWidgetPosition(position, id: widget.id)
        return true
    }

    private func addWidget(_ kind: DesktopWidgetKind) {
        let id = model.addWidget(kind: kind, for: selectedDisplay?.id)
        selectedWidgetID = id
    }

    private func duplicateSelectedWidget(_ widget: DesktopWidget) {
        if let id = model.duplicateWidget(id: widget.id, for: selectedDisplay?.id) {
            selectedWidgetID = id
            DispatchQueue.main.async {
                syncEditorState()
                selectedWidgetID = id
            }
        }
    }

    private func syncEditorState() {
        previewPositions = Dictionary(
            uniqueKeysWithValues: editableWidgets.map { ($0.id, $0.position) }
        )
        previewCustomScales = Dictionary(
            uniqueKeysWithValues: editableWidgets.map { ($0.id, $0.renderingScale) }
        )
        if let selectedWidgetID,
           editableWidgets.contains(where: { $0.id == selectedWidgetID }) {
            return
        }
        selectedWidgetID = editableWidgets.last?.id
    }

    private func selectInitialDisplayIfNeeded() {
        let activeIDs = model.displayTopology.activeDisplayIDs
        if let id = model.selectedDisplayID, activeIDs.contains(id) { return }
        model.selectedDisplayID = model.displayTopology.displays
            .first(where: { $0.isMain })?.id
            ?? model.displayTopology.displays.first?.id
    }

    private func widgetDisplayName(_ widget: DesktopWidget) -> String {
        let sameName = editableWidgets.filter {
            widgetBaseName($0) == widgetBaseName(widget)
        }
        let base = widgetBaseName(widget)
        guard sameName.count > 1,
              let index = sameName.firstIndex(where: { $0.id == widget.id }) else {
            return base
        }
        return "\(base) \(index + 1)"
    }

    private func widgetBaseName(_ widget: DesktopWidget) -> String {
        if widget.kind == .dateCalendar {
            return widget.dateCalendar.mode == .monthCalendar
                ? "Month Calendar"
                : "Date"
        }
        return widgetName(widget.kind)
    }

    private func widgetName(_ kind: DesktopWidgetKind) -> String {
        switch kind {
        case .digitalClock: return "Digital Clock"
        case .nowPlaying: return "Now Playing"
        case .dateCalendar: return "Date & Calendar"
        case .battery: return "Battery"
        case .weather: return "Weather"
        }
    }

    private func widgetIcon(_ kind: DesktopWidgetKind) -> String {
        switch kind {
        case .digitalClock: return "clock"
        case .nowPlaying: return "music.note"
        case .dateCalendar: return "calendar"
        case .battery: return "battery.75percent"
        case .weather: return "cloud.sun.fill"
        }
    }

    private func widgetSubtitle(_ kind: DesktopWidgetKind) -> String {
        switch kind {
        case .digitalClock:
            return "A clean, glanceable time display"
        case .nowPlaying:
            return "Artwork, progress, and playback activity"
        case .dateCalendar:
            return "A date display or clean month overview"
        case .battery:
            return "Current power level and charging state"
        case .weather:
            return "Temperature and conditions for your location"
        }
    }

    private func defaultPosition(_ kind: DesktopWidgetKind) -> NormalizedWidgetPosition {
        switch kind {
        case .digitalClock: return NormalizedWidgetPosition(x: 0.5, y: 0.18)
        case .nowPlaying: return NormalizedWidgetPosition(x: 0.5, y: 0.78)
        case .dateCalendar: return NormalizedWidgetPosition(x: 0.18, y: 0.20)
        case .battery: return NormalizedWidgetPosition(x: 0.82, y: 0.20)
        case .weather: return NormalizedWidgetPosition(x: 0.82, y: 0.78)
        }
    }

    private func selectionCornerRadius(_ widget: DesktopWidget) -> CGFloat {
        switch (widget.kind, widget.size) {
        case (.digitalClock, .small), (.nowPlaying, .small): return 16
        case (.digitalClock, .large): return 25
        case (.nowPlaying, .large): return 27
        case (.dateCalendar, .large), (.battery, .large), (.weather, .large): return 27
        case (.dateCalendar, .small), (.battery, .small), (.weather, .small): return 16
        case (.digitalClock, _): return 20
        case (.nowPlaying, _), (.dateCalendar, _), (.battery, _), (.weather, _): return 21
        }
    }

    private var modeDescription: String {
        model.widgetDisplayMode == .mirrored
            ? "Edit one shared layout, then hide it on individual monitors when needed."
            : "Each monitor keeps its own widgets, positions, and appearance settings."
    }

    private var footerText: String {
        model.widgetDisplayMode == .mirrored
            ? "Mirror keeps one layout synchronized across displays while allowing per-monitor visibility."
            : "Per Display lets every monitor keep a different widget layout."
    }

    private var removalConfirmationTitle: String {
        guard let id = pendingRemovalID,
              let widget = editableWidgets.first(where: { $0.id == id }) else {
            return "Remove widget?"
        }
        return "Remove \(widgetDisplayName(widget))?"
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

private struct WidgetMeasuredSizePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGSize] = [:]

    static func reduce(
        value: inout [UUID: CGSize],
        nextValue: () -> [UUID: CGSize]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct WidgetKeyboardMonitor: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var handler: (NSEvent) -> Bool
        private var monitor: Any?
        private weak var view: NSView?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
        }

        func attach(to view: NSView) {
            self.view = view
            start()
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let view = self.view,
                      NSApp.keyWindow === view.window else {
                    return event
                }
                if let responder = NSApp.keyWindow?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }
                return self.handler(event) ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }
    }
}

private struct WidgetChooserView: View {
    let add: (DesktopWidgetKind) -> Void

    private let columns = [
        GridItem(.fixed(190), spacing: 12),
        GridItem(.fixed(190), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add Widget")
                    .font(.headline)
                Text("Choose something useful at a glance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                chooserCard(
                    kind: .digitalClock,
                    title: "Digital Clock",
                    description: "Time with optional seconds."
                )
                chooserCard(
                    kind: .nowPlaying,
                    title: "Now Playing",
                    description: "Artwork and playback progress."
                )
                chooserCard(
                    kind: .dateCalendar,
                    title: "Date & Calendar",
                    description: "Date or full month overview."
                )
                chooserCard(
                    kind: .battery,
                    title: "Battery",
                    description: "Power level and charging state."
                )
                chooserCard(
                    kind: .weather,
                    title: "Weather",
                    description: "Temperature and conditions."
                )
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func chooserCard(
        kind: DesktopWidgetKind,
        title: String,
        description: String
    ) -> some View {
        Button {
            add(kind)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: icon(kind))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                }

                chooserPreview(kind)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.86),
                                Color.gray.opacity(0.48)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(width: 190, height: 124, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func chooserPreview(_ kind: DesktopWidgetKind) -> some View {
        switch kind {
        case .digitalClock:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("10:39")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                Text("AM")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .widgetSurface(style: .glass, cornerRadius: 10, scale: 0.5)

        case .nowPlaying:
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.10))
                    .frame(width: 31, height: 31)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing Playing")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                    Text("Play audio to see it here")
                        .font(.system(size: 6, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                    Capsule()
                        .fill(.white.opacity(0.20))
                        .frame(width: 55, height: 2)
                }
            }
            .foregroundStyle(.white)
            .padding(7)
            .widgetSurface(style: .glass, cornerRadius: 10, scale: 0.5)

        case .dateCalendar:
            HStack(alignment: .center, spacing: 7) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("WED")
                        .font(.system(size: 6, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.58))
                    Text("JUL")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                Text("15")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .widgetSurface(style: .glass, cornerRadius: 10, scale: 0.5)

        case .battery:
            HStack(spacing: 7) {
                Image(systemName: "battery.100percent")
                    .font(.system(size: 16, weight: .medium))
                VStack(alignment: .leading, spacing: 2) {
                    Text("100%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Charged")
                        .font(.system(size: 6, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                    Capsule()
                        .fill(.white.opacity(0.78))
                        .frame(width: 49, height: 2)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .widgetSurface(style: .glass, cornerRadius: 10, scale: 0.5)

        case .weather:
            HStack(spacing: 7) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 16, weight: .medium))
                    .symbolRenderingMode(.multicolor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("72°")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Partly Cloudy")
                        .font(.system(size: 6, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .widgetSurface(style: .glass, cornerRadius: 10, scale: 0.5)
        }
    }

    private func icon(_ kind: DesktopWidgetKind) -> String {
        switch kind {
        case .digitalClock: return "clock"
        case .nowPlaying: return "music.note"
        case .dateCalendar: return "calendar"
        case .battery: return "battery.75percent"
        case .weather: return "cloud.sun.fill"
        }
    }
}
