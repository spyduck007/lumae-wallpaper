import AppKit
import SwiftUI
import LumaeCore

struct WidgetsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var previewPosition = NormalizedWidgetPosition()
    @State private var confirmRemoval = false
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
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
        .onAppear(perform: syncPreviewPosition)
        .onChange(of: model.digitalClockWidget?.position) { _, _ in
            if !isDragging {
                syncPreviewPosition()
            }
        }
        .confirmationDialog(
            "Remove the clock widget?",
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Clock", role: .destructive) {
                if let widget = model.digitalClockWidget {
                    model.removeWidget(id: widget.id)
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

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wallpaper Preview")
                    .font(.headline)

                Spacer()

                Label("Applies to every display", systemImage: "display.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack {
                    previewWallpaper

                    if let widget = model.digitalClockWidget {
                        DigitalClockWidgetView(widget: previewWidget(widget))
                            .overlay {
                                RoundedRectangle(cornerRadius: selectionCornerRadius(widget.size), style: .continuous)
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
                                DragGesture(minimumDistance: 1, coordinateSpace: .named("widgetPreview"))
                                    .onChanged { value in
                                        isDragging = true
                                        previewPosition = normalizedPosition(
                                            for: value.location,
                                            in: proxy.size
                                        )
                                    }
                                    .onEnded { value in
                                        let position = normalizedPosition(
                                            for: value.location,
                                            in: proxy.size
                                        )
                                        previewPosition = position
                                        isDragging = false
                                        model.setWidgetPosition(position, id: widget.id)
                                    }
                            )
                            .help("Drag to reposition the clock")
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "clock.badge.plus")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(.secondary)

                            Text("No Widgets Yet")
                                .font(.title3.bold())

                            Text("Start with a clean digital clock.")
                                .foregroundStyle(.secondary)

                            Button("Add Digital Clock") {
                                let id = model.addDigitalClockWidget()
                                if let widget = model.widgets.first(where: { $0.id == id }) {
                                    previewPosition = widget.position
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .padding(28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private var footerNote: some View {
        Label(
            "For this first version, the same clock and position are mirrored across all active wallpaper displays.",
            systemImage: "info.circle"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let widget = model.digitalClockWidget {
                    inspectorHeader
                    appearanceCard(widget)
                    timeCard(widget)
                    placementCard(widget)
                    removalCard
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.tint)

                        Text("Add a Widget")
                            .font(.title3.bold())

                        Text("Widgets stay behind your desktop icons and never capture mouse input outside this editor.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Add Digital Clock") {
                            let id = model.addDigitalClockWidget()
                            if let widget = model.widgets.first(where: { $0.id == id }) {
                                previewPosition = widget.position
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
    }

    private var inspectorHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text("Digital Clock")
                    .font(.title3.bold())
                Text("Displayed on every monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func appearanceCard(_ widget: DesktopWidget) -> some View {
        WidgetInspectorCard(title: "Appearance") {
            Toggle(
                "Show clock",
                isOn: Binding(
                    get: { widget.isEnabled },
                    set: { model.setWidgetEnabled($0, id: widget.id) }
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
            }
            .pickerStyle(.segmented)
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
            Text("Drag the clock in the preview to place it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Reset to Top Center") {
                let position = NormalizedWidgetPosition(x: 0.5, y: 0.18)
                previewPosition = position
                model.setWidgetPosition(position, id: widget.id)
            }
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

    private var representativeWallpaper: WallpaperMetadata? {
        switch model.state.settings.presentationMode {
        case .duplicate, .span:
            if let wallpaper = model.wallpaper(id: model.state.sharedWallpaperID) {
                return wallpaper
            }
        case .perDisplay:
            if let mainDisplay = model.displayTopology.displays.first(where: { $0.isMain })
                ?? model.displayTopology.displays.first {
                let assignment = model.displayAssignment(for: mainDisplay)
                if let wallpaper = model.wallpaper(id: assignment.wallpaperID) {
                    return wallpaper
                }
            }
        }

        return model.assignableWallpapers.first
    }

    private func previewWidget(_ widget: DesktopWidget) -> DesktopWidget {
        var copy = widget
        copy.position = previewPosition
        return copy
    }

    private func normalizedPosition(
        for location: CGPoint,
        in size: CGSize
    ) -> NormalizedWidgetPosition {
        let minimumX = 0.10
        let maximumX = 0.90
        let minimumY = 0.12
        let maximumY = 0.88

        let x = min(max(location.x / max(size.width, 1), minimumX), maximumX)
        let y = min(max(location.y / max(size.height, 1), minimumY), maximumY)
        return NormalizedWidgetPosition(x: x, y: y)
    }

    private func selectionCornerRadius(_ size: DesktopWidgetSize) -> CGFloat {
        switch size {
        case .small: return 14
        case .medium: return 18
        case .large: return 22
        }
    }

    private func syncPreviewPosition() {
        previewPosition = model.digitalClockWidget?.position
            ?? NormalizedWidgetPosition()
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
