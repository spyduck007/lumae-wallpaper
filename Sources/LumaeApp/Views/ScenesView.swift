import AppKit
import SwiftUI
import LumaeCore

struct ScenesView: View {
    @EnvironmentObject private var model: AppModel

    @State private var selectedSceneID: UUID?
    @State private var renameSceneID: UUID?
    @State private var renameText = ""
    @State private var deleteSceneID: UUID?
    @State private var overwriteSceneID: UUID?
    @State private var isActivating = false

    var body: some View {
        HStack(spacing: 0) {
            sceneList
                .frame(width: 250)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedSceneID == nil {
                selectedSceneID = model.state.activeSceneID ?? model.scenes.first?.id
            }
        }
        .onChange(of: model.scenes) { _, scenes in
            if let selectedSceneID,
               scenes.contains(where: { $0.id == selectedSceneID }) {
                return
            }
            selectedSceneID = model.state.activeSceneID ?? scenes.first?.id
        }
        .alert("Rename Scene", isPresented: renameAlertBinding) {
            TextField("Scene name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameSceneID = nil
            }
            Button("Rename") {
                guard let renameSceneID else { return }
                _ = model.renameScene(id: renameSceneID, to: renameText)
                self.renameSceneID = nil
            }
        } message: {
            Text("Choose a short name that describes this desktop setup.")
        }
        .confirmationDialog(
            "Replace this scene with the current setup?",
            isPresented: overwriteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Save Current Setup", role: .destructive) {
                guard let overwriteSceneID else { return }
                model.saveCurrentSetup(toScene: overwriteSceneID)
                self.overwriteSceneID = nil
            }
            Button("Cancel", role: .cancel) {
                overwriteSceneID = nil
            }
        } message: {
            Text("The scene’s previous wallpaper, playlist, display, and widget configuration will be replaced.")
        }
        .confirmationDialog(
            "Delete this scene?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Scene", role: .destructive) {
                guard let deleteSceneID else { return }
                model.deleteScene(id: deleteSceneID)
                self.deleteSceneID = nil
            }
            Button("Cancel", role: .cancel) {
                deleteSceneID = nil
            }
        } message: {
            Text("Your wallpapers, playlists, and widgets are not deleted—only this saved scene snapshot.")
        }
    }

    private var sceneList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scenes")
                        .font(.headline)
                    Text("Complete desktop setups")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    let id = model.createScene(named: "New Scene")
                    selectedSceneID = id
                    beginRename(id)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Save the current setup as a new scene")
            }
            .padding(16)

            Divider()

            if model.scenes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Scenes Yet")
                        .font(.headline)
                    Text("Save the current desktop setup, then switch back to it anytime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Save Current Setup") {
                        let id = model.createScene(named: "My Scene")
                        selectedSceneID = id
                        beginRename(id)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedSceneID) {
                    ForEach(model.scenes) { scene in
                        sceneRow(scene)
                            .tag(scene.id)
                            .contextMenu {
                                sceneActions(scene)
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private func sceneRow(_ scene: DesktopScene) -> some View {
        HStack(spacing: 9) {
            Image(systemName: model.state.activeSceneID == scene.id
                ? "checkmark.circle.fill"
                : "circle")
                .foregroundStyle(
                    model.state.activeSceneID == scene.id
                        ? Color.accentColor
                        : Color.secondary.opacity(0.45)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(scene.name)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if model.state.defaultSceneID == scene.id {
                        Label("Default", systemImage: "star.fill")
                    }
                    if model.state.activeSceneID == scene.id,
                       model.activeSceneHasChanges {
                        Text("Modified")
                    }
                    let missing = model.sceneMissingWallpaperCount(scene)
                    if missing > 0 {
                        Label("\(missing) missing", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedSceneID,
           let scene = model.scene(id: selectedSceneID) {
            sceneDetail(scene)
        } else {
            ContentUnavailableView(
                "Select a Scene",
                systemImage: "square.stack.3d.up",
                description: Text("Scenes save your wallpaper, display, playlist, and widget setup together.")
            )
        }
    }

    private func sceneDetail(_ scene: DesktopScene) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(scene.name)
                                .font(.largeTitle.bold())

                            if model.state.activeSceneID == scene.id {
                                sceneBadge(
                                    model.activeSceneHasChanges ? "Modified" : "Active",
                                    systemImage: model.activeSceneHasChanges
                                        ? "pencil.circle.fill"
                                        : "checkmark.circle.fill",
                                    color: model.activeSceneHasChanges ? .orange : .green
                                )
                            }

                            if model.state.defaultSceneID == scene.id {
                                sceneBadge("Default", systemImage: "star.fill", color: .yellow)
                            }
                        }

                        Text("A complete snapshot of your Lumae desktop environment.")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if model.state.activeSceneID != scene.id || model.activeSceneHasChanges {
                        Button {
                            Task { await activate(scene.id) }
                        } label: {
                            if isActivating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Activate", systemImage: "play.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isActivating)
                    }

                    Menu {
                        sceneActions(scene)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if model.state.activeSceneID == scene.id,
                   model.activeSceneHasChanges {
                    HStack(spacing: 12) {
                        Image(systemName: "pencil.and.list.clipboard")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current setup differs from this scene")
                                .font(.headline)
                            Text("Save the current setup to update the scene, or activate it to restore the saved version.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Save Current Setup") {
                            overwriteSceneID = scene.id
                        }
                    }
                    .padding(14)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }

                sceneSummary(scene)

                Divider()

                HStack {
                    Text("Updated \(scene.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save Current Setup") {
                        overwriteSceneID = scene.id
                    }
                    .disabled(
                        model.state.activeSceneID == scene.id
                            && !model.activeSceneHasChanges
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private func sceneSummary(_ scene: DesktopScene) -> some View {
        let configuration = scene.configuration
        let enabledDisplays = configuration.assignments.filter(\.enabled).count
        let widgetCount = configuration.widgetDisplayMode == .mirrored
            ? configuration.widgets.count
            : configuration.widgetDisplayConfigurations.reduce(0) { $0 + $1.widgets.count }
        let runningPlaylist = configuration.playlists.first {
            $0.id == configuration.activePlaylistID && $0.isRunning
        }

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ],
            spacing: 14
        ) {
            summaryCard(
                title: "Wallpaper",
                systemImage: "photo.on.rectangle",
                primary: wallpaperSummary(configuration),
                secondary: presentationLabel(configuration.playback.presentationMode)
            )
            summaryCard(
                title: "Displays",
                systemImage: "display.2",
                primary: "\(enabledDisplays) enabled",
                secondary: configuration.assignments.isEmpty
                    ? "Uses connected display defaults"
                    : "\(configuration.assignments.count) saved assignments"
            )
            summaryCard(
                title: "Widgets",
                systemImage: "square.stack.3d.up",
                primary: "\(widgetCount) widget\(widgetCount == 1 ? "" : "s")",
                secondary: configuration.widgetDisplayMode == .mirrored
                    ? "Mirrored layout"
                    : "Per-display layouts"
            )
            summaryCard(
                title: "Playlist",
                systemImage: "music.note.list",
                primary: runningPlaylist?.name ?? "No active rotation",
                secondary: "\(configuration.playlists.count) saved playlist\(configuration.playlists.count == 1 ? "" : "s")"
            )
        }
    }

    private func summaryCard(
        title: String,
        systemImage: String,
        primary: String,
        secondary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(primary)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
            Text(secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func sceneActions(_ scene: DesktopScene) -> some View {
        Button("Activate") {
            Task { await activate(scene.id) }
        }
        .disabled(isActivating || (model.state.activeSceneID == scene.id && !model.activeSceneHasChanges))

        Button("Save Current Setup") {
            overwriteSceneID = scene.id
        }

        Divider()

        Button("Rename…") {
            beginRename(scene.id)
        }

        Button("Duplicate") {
            if let id = model.duplicateScene(id: scene.id) {
                selectedSceneID = id
            }
        }

        Button(model.state.defaultSceneID == scene.id ? "Remove as Default" : "Set as Default") {
            model.setDefaultScene(
                id: model.state.defaultSceneID == scene.id ? nil : scene.id
            )
        }

        Divider()

        Button("Delete…", role: .destructive) {
            deleteSceneID = scene.id
        }
    }

    private func activate(_ id: UUID) async {
        guard !isActivating else { return }
        isActivating = true
        defer { isActivating = false }
        await model.activateScene(id: id)
    }

    private func beginRename(_ id: UUID) {
        renameSceneID = id
        renameText = model.scene(id: id)?.name ?? ""
    }

    private func wallpaperSummary(_ configuration: SceneConfiguration) -> String {
        switch configuration.playback.presentationMode {
        case .perDisplay:
            let names = configuration.assignments
                .filter(\.enabled)
                .compactMap { assignment in
                    model.wallpaper(id: assignment.wallpaperID)?.name
                }
            if names.isEmpty { return "No wallpaper assigned" }
            if Set(names).count == 1 { return names[0] }
            return "\(Set(names).count) wallpapers"
        case .duplicate, .span:
            return model.wallpaper(id: configuration.sharedWallpaperID)?.name
                ?? "No wallpaper assigned"
        }
    }

    private func presentationLabel(_ mode: DisplayPresentationMode) -> String {
        switch mode {
        case .perDisplay: return "Per-display presentation"
        case .duplicate: return "Duplicated across displays"
        case .span: return "Spanned across displays"
        }
    }

    private func sceneBadge(
        _ text: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: Capsule())
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameSceneID != nil },
            set: { if !$0 { renameSceneID = nil } }
        )
    }

    private var overwriteDialogBinding: Binding<Bool> {
        Binding(
            get: { overwriteSceneID != nil },
            set: { if !$0 { overwriteSceneID = nil } }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { deleteSceneID != nil },
            set: { if !$0 { deleteSceneID = nil } }
        )
    }
}
