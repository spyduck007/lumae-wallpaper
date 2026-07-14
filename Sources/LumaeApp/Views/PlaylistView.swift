import AppKit
import SwiftUI
import LumaeCore

struct PlaylistView: View {
    @EnvironmentObject private var model: AppModel
    let playlistID: UUID
    let onDelete: () -> Void

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var confirmDelete = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        if let playlist = model.playlist(id: playlistID) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header(playlist)
                    Divider()
                    queue(playlist)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                inspector(playlist)
                    .frame(width: 350)
            }
            .onAppear {
                draftName = playlist.name
            }
            .onChange(of: playlist.name) { _, newValue in
                if !isRenaming { draftName = newValue }
            }
            .confirmationDialog(
                "Delete “\(playlist.name)”?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive) {
                    model.deletePlaylist(id: playlistID)
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Wallpapers remain in your library.")
            }
        } else {
            ContentUnavailableView(
                "Playlist Not Found",
                systemImage: "music.note.list",
                description: Text("This playlist may have been deleted.")
            )
        }
    }

    private func header(_ playlist: WallpaperPlaylist) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                if isRenaming {
                    TextField("Playlist name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .onSubmit(saveName)
                        .frame(maxWidth: 320)
                } else {
                    HStack(spacing: 8) {
                        Text(playlist.name)
                            .font(.title2.bold())

                        Button(action: beginRename) {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("Rename playlist")
                    }
                }

                Text(queueSummary(playlist))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isRenaming {
                Button("Cancel", action: cancelRename)
                Button("Save", action: saveName)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Menu {
                    let available = model.assignableWallpapers.filter {
                        !playlist.wallpaperIDs.contains($0.id)
                    }
                    if available.isEmpty {
                        Text("No wallpapers available")
                    } else {
                        ForEach(available) { wallpaper in
                            Button {
                                model.addWallpaper(wallpaper.id, toPlaylist: playlistID)
                            } label: {
                                Label(
                                    wallpaper.name,
                                    systemImage: wallpaper.kind == .video
                                        ? "play.rectangle"
                                        : "photo"
                                )
                            }
                        }
                    }
                } label: {
                    Label("Add Wallpaper", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private func queue(_ playlist: WallpaperPlaylist) -> some View {
        if playlist.wallpaperIDs.isEmpty {
            ContentUnavailableView {
                Label("Empty Playlist", systemImage: "music.note.list")
            } description: {
                Text("Add wallpapers to create an automatic rotation.")
            } actions: {
                Menu("Add Wallpaper") {
                    ForEach(model.assignableWallpapers) { wallpaper in
                        Button(wallpaper.name) {
                            model.addWallpaper(wallpaper.id, toPlaylist: playlistID)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(Array(playlist.wallpaperIDs.enumerated()), id: \.element) { index, wallpaperID in
                    PlaylistQueueRow(
                        index: index,
                        wallpaper: model.wallpaper(id: wallpaperID),
                        isCurrent: playlist.currentWallpaperID == wallpaperID,
                        canMoveUp: index > 0,
                        canMoveDown: index + 1 < playlist.wallpaperIDs.count,
                        moveUp: {
                            model.moveWallpaperUp(wallpaperID, inPlaylist: playlistID)
                        },
                        moveDown: {
                            model.moveWallpaperDown(wallpaperID, inPlaylist: playlistID)
                        },
                        remove: {
                            model.removeWallpaper(
                                at: IndexSet(integer: index),
                                fromPlaylist: playlistID
                            )
                        }
                    )
                }
                .onMove { source, destination in
                    model.moveWallpaper(
                        inPlaylist: playlistID,
                        from: source,
                        to: destination
                    )
                }
            }
            .listStyle(.inset)
        }
    }

    private func inspector(_ playlist: WallpaperPlaylist) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                playbackCard(playlist)
                timingCard(playlist)
                targetCard(playlist)
                playlistInfoCard(playlist)
                deleteCard
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
    }

    private func playbackCard(_ playlist: WallpaperPlaylist) -> some View {
        PlaylistInspectorCard(title: "Playback") {
            HStack(spacing: 12) {
                Button {
                    model.advanceActivePlaylist(.previous)
                } label: {
                    Image(systemName: "backward.fill")
                        .frame(width: 24, height: 24)
                }
                .disabled(model.state.activePlaylistID != playlist.id || playlist.wallpaperIDs.isEmpty)
                .help("Previous wallpaper")

                Button {
                    if model.state.activePlaylistID == playlist.id {
                        model.toggleActivePlaylist()
                    } else {
                        model.startPlaylist(id: playlist.id)
                    }
                } label: {
                    Label(
                        playButtonTitle(playlist),
                        systemImage: playButtonIcon(playlist)
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    if model.state.activePlaylistID != playlist.id {
                        model.startPlaylist(id: playlist.id)
                    } else {
                        model.advanceActivePlaylist(.next)
                    }
                } label: {
                    Image(systemName: "forward.fill")
                        .frame(width: 24, height: 24)
                }
                .disabled(playlist.wallpaperIDs.isEmpty)
                .help("Next wallpaper")
            }

            if model.state.activePlaylistID == playlist.id {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Circle()
                            .fill(playlist.isRunning ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(statusText(playlist, now: context.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Starting this playlist pauses any other active playlist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timingCard(_ playlist: WallpaperPlaylist) -> some View {
        PlaylistInspectorCard(title: "Rotation") {
            Toggle(
                "Shuffle",
                isOn: Binding(
                    get: { playlist.shuffle },
                    set: { model.setPlaylistShuffle($0, id: playlistID) }
                )
            )

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Change wallpaper every")
                    .font(.callout.weight(.medium))

                Picker(
                    "Interval",
                    selection: Binding(
                        get: { playlist.intervalSeconds },
                        set: { model.setPlaylistInterval($0, id: playlistID) }
                    )
                ) {
                    Text("10 seconds (testing)").tag(TimeInterval(10))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("15 minutes").tag(TimeInterval(900))
                    Text("30 minutes").tag(TimeInterval(1_800))
                    Text("1 hour").tag(TimeInterval(3_600))
                    Text("2 hours").tag(TimeInterval(7_200))
                    Text("6 hours").tag(TimeInterval(21_600))
                    Text("12 hours").tag(TimeInterval(43_200))
                    Text("24 hours").tag(TimeInterval(86_400))
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Stepper(
                    "Custom: \(customMinutes(playlist.intervalSeconds)) min",
                    value: Binding(
                        get: { customMinutes(playlist.intervalSeconds) },
                        set: { model.setPlaylistInterval(TimeInterval($0 * 60), id: playlistID) }
                    ),
                    in: 1...1_440
                )
                .font(.caption)
            }
        }
    }

    private func targetCard(_ playlist: WallpaperPlaylist) -> some View {
        PlaylistInspectorCard(title: "Target") {
            Picker(
                "Target",
                selection: Binding(
                    get: { playlist.target },
                    set: { model.setPlaylistTarget($0, id: playlistID) }
                )
            ) {
                Label("Current Presentation", systemImage: "rectangle.3.group")
                    .tag(PlaylistTarget.currentPresentation)

                ForEach(model.displayTopology.displays) { display in
                    Label(
                        display.fingerprint.localizedName,
                        systemImage: display.isBuiltIn ? "laptopcomputer" : "display"
                    )
                    .tag(PlaylistTarget.display(display.fingerprint))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Text(targetDescription(playlist.target))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func playlistInfoCard(_ playlist: WallpaperPlaylist) -> some View {
        PlaylistInspectorCard(title: "Queue") {
            PlaylistValueRow(title: "Wallpapers", value: "\(playlist.wallpaperIDs.count)")
            PlaylistValueRow(
                title: "Available",
                value: "\(availableCount(playlist))"
            )
            PlaylistValueRow(
                title: "Order",
                value: playlist.shuffle ? "Shuffled" : "Sequential"
            )

            if let current = model.wallpaper(id: playlist.currentWallpaperID) {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Currently showing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(current.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                }
            }
        }
    }

    private var deleteCard: some View {
        PlaylistInspectorCard(title: "Playlist") {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Playlist", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func beginRename() {
        draftName = model.playlist(id: playlistID)?.name ?? ""
        isRenaming = true
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func cancelRename() {
        draftName = model.playlist(id: playlistID)?.name ?? ""
        isRenaming = false
        nameFieldFocused = false
    }

    private func saveName() {
        guard model.renamePlaylist(id: playlistID, to: draftName) else { return }
        draftName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = false
        nameFieldFocused = false
    }

    private func queueSummary(_ playlist: WallpaperPlaylist) -> String {
        let count = playlist.wallpaperIDs.count
        return "\(count) wallpaper\(count == 1 ? "" : "s") • \(intervalLabel(playlist.intervalSeconds))"
    }

    private func playButtonTitle(_ playlist: WallpaperPlaylist) -> String {
        guard model.state.activePlaylistID == playlist.id else { return "Start" }
        return playlist.isRunning ? "Pause" : "Resume"
    }

    private func playButtonIcon(_ playlist: WallpaperPlaylist) -> String {
        guard model.state.activePlaylistID == playlist.id else { return "play.fill" }
        return playlist.isRunning ? "pause.fill" : "play.fill"
    }

    private func statusText(_ playlist: WallpaperPlaylist, now: Date) -> String {
        guard playlist.isRunning else { return "Paused" }
        let elapsed = playlist.lastAdvancedAt.map { now.timeIntervalSince($0) } ?? 0
        let remaining = max(Int(playlist.intervalSeconds - elapsed), 0)
        return "Next change in \(durationLabel(remaining))"
    }

    private func targetDescription(_ target: PlaylistTarget) -> String {
        switch target {
        case .currentPresentation:
            return "Rotates the shared wallpaper or all per-display assignments using the current Display Layout mode."
        case .display(let fingerprint):
            return "Rotates only \(fingerprint.localizedName). Lumae switches to Per Display mode when needed."
        }
    }

    private func availableCount(_ playlist: WallpaperPlaylist) -> Int {
        playlist.wallpaperIDs.filter { id in
            guard let wallpaper = model.wallpaper(id: id) else { return false }
            return !wallpaper.isMissing && wallpaper.kind != .unsupported
        }.count
    }

    private func customMinutes(_ seconds: TimeInterval) -> Int {
        max(Int((seconds / 60).rounded()), 1)
    }

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        durationLabel(Int(seconds))
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}

private struct PlaylistQueueRow: View {
    let index: Int
    let wallpaper: WallpaperMetadata?
    let isCurrent: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            if let wallpaper {
                WallpaperThumbnail(item: wallpaper, animate: false)
                    .frame(width: 88, height: 55)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(wallpaper.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if isCurrent {
                            Text("Current")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.2), in: Capsule())
                        }
                    }

                    Text(wallpaper.isMissing
                        ? "Missing file"
                        : "\(wallpaper.pixelWidth) × \(wallpaper.pixelHeight) • \(wallpaper.format.rawValue.uppercased())")
                        .font(.caption)
                        .foregroundStyle(wallpaper.isMissing ? Color.red : Color.secondary)
                }
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .font(.title2)
                    .frame(width: 88, height: 55)

                Text("Wallpaper no longer exists")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 5) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .help("Move up")

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .help("Move down")

                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove from playlist")
            }
        }
        .padding(.vertical, 5)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.09) : Color.clear)
    }
}

private struct PlaylistInspectorCard<Content: View>: View {
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

private struct PlaylistValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }
}
