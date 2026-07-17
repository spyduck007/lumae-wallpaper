import AppKit
import SwiftUI
import LumaeCore

struct WallpaperInspectorView: View {
    @EnvironmentObject private var model: AppModel

    let wallpaper: WallpaperMetadata
    let openDisplayLayout: () -> Void

    @State private var confirmRemoval = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                preview
                primaryActions
                metadataSection
                if wallpaper.kind == .video {
                    optimizationSection
                }
                fileSection
                destructiveSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
        .onAppear {
            draftName = wallpaper.name
        }
        .onChange(of: wallpaper.id) { _, _ in
            isRenaming = false
            draftName = wallpaper.name
        }
        .onChange(of: wallpaper.name) { _, newName in
            if !isRenaming {
                draftName = newName
            }
        }
        .confirmationDialog(
            "Remove “\(wallpaper.name)” from Lumae?",
            isPresented: $confirmRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove from Lumae", role: .destructive) {
                model.remove(wallpaper)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original media file will not be deleted.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: wallpaper.kind == .video ? "play.rectangle" : "photo")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                if isRenaming {
                    TextField("Wallpaper name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .onSubmit(commitRename)
                        .accessibilityLabel("Wallpaper name")
                } else {
                    Text(wallpaper.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                HStack(spacing: 7) {
                    statusBadge
                    Text(wallpaper.format.rawValue.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isRenaming {
                HStack(spacing: 6) {
                    Button(action: cancelRename) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel rename")
                    .accessibilityLabel("Cancel rename")

                    Button(action: commitRename) {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Save wallpaper name")
                    .accessibilityLabel("Save wallpaper name")
                    .disabled(
                        draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            } else {
                HStack(spacing: 6) {
                    Button(action: beginRename) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Rename wallpaper")
                    .accessibilityLabel("Rename wallpaper")

                    Button {
                        model.selectedWallpaperID = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Close inspector")
                    .accessibilityLabel("Close wallpaper inspector")
                }
            }
        }
    }

    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            WallpaperThumbnail(item: wallpaper, animate: false)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if wallpaper.kind == .video {
                Label("Video", systemImage: "play.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(9)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var primaryActions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await model.apply(wallpaper) }
            } label: {
                Label("Apply Wallpaper", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(wallpaper.isMissing)

            HStack(spacing: 10) {
                Button {
                    model.toggleFavorite(wallpaper)
                } label: {
                    Label(
                        wallpaper.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: wallpaper.isFavorite ? "star.slash" : "star"
                    )
                    .frame(maxWidth: .infinity)
                }

                Button(action: openDisplayLayout) {
                    Label("Displays", systemImage: "display.2")
                        .frame(maxWidth: .infinity)
                }
                .help("Open Display Layout for per-monitor assignment and scaling")
            }

            Menu {
                if model.playlists.isEmpty {
                    Button("Create New Playlist") {
                        let id = model.createPlaylist()
                        model.addWallpaper(wallpaper.id, toPlaylist: id)
                    }
                } else {
                    ForEach(model.playlists) { playlist in
                        Button {
                            model.addWallpaper(wallpaper.id, toPlaylist: playlist.id)
                        } label: {
                            if playlist.wallpaperIDs.contains(wallpaper.id) {
                                Label(playlist.name, systemImage: "checkmark")
                            } else {
                                Text(playlist.name)
                            }
                        }
                        .disabled(playlist.wallpaperIDs.contains(wallpaper.id))
                    }

                    Divider()

                    Button("New Playlist with This Wallpaper") {
                        let id = model.createPlaylist()
                        model.addWallpaper(wallpaper.id, toPlaylist: id)
                    }
                }
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var metadataSection: some View {
        InspectorSection(title: "Details") {
            InspectorValueRow(title: "Dimensions", value: "\(wallpaper.pixelWidth) × \(wallpaper.pixelHeight)")
            InspectorValueRow(title: "File size", value: byteCountFormatter.string(fromByteCount: wallpaper.fileSizeBytes))

            if let duration = wallpaper.durationSeconds {
                InspectorValueRow(title: "Duration", value: durationFormatter(duration))
            }

            if let frameRate = wallpaper.frameRate, frameRate > 0 {
                InspectorValueRow(title: "Frame rate", value: String(format: "%.1f fps", frameRate))
            }

            InspectorValueRow(title: "Added", value: wallpaper.dateAdded.formatted(date: .abbreviated, time: .shortened))

            if let lastUsed = wallpaper.dateLastUsed {
                InspectorValueRow(title: "Last used", value: lastUsed.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var optimizationSection: some View {
        InspectorSection(title: "Playback") {
            switch model.videoOptimizationState(for: wallpaper) {
            case .original:
                Label(
                    "Original media",
                    systemImage: "film"
                )
                .font(.callout.weight(.medium))

                Text(
                    "Lumae prepares a smaller playback copy automatically when the selected quality or frame-rate limit would reduce decoding work."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if model.canOptimizeVideo(wallpaper) {
                    Button {
                        model.optimizeVideo(wallpaper)
                    } label: {
                        Label("Optimize Now", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                }

            case let .preparing(profile, progress):
                HStack {
                    Label("Preparing optimized copy", systemImage: "gearshape.2")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                Text(profileDescription(profile))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case let .available(profile, size):
                Label("Optimized playback", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                InspectorValueRow(
                    title: "Profile",
                    value: profileDescription(profile)
                )
                InspectorValueRow(
                    title: "Cached size",
                    value: byteCountFormatter.string(fromByteCount: size)
                )
                Text("The original media remains unchanged and is used whenever higher quality is requested.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.removeOptimizedVideo(wallpaper)
                } label: {
                    Label("Remove Optimized Copy", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }

            case let .failed(message):
                Label("Using original media", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    model.optimizeVideo(wallpaper)
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var fileSection: some View {
        InspectorSection(title: "File") {
            Text(wallpaper.effectiveFilePath)
                .font(.caption.monospaced())
                .foregroundStyle(wallpaper.isMissing ? .red : .secondary)
                .textSelection(.enabled)
                .lineLimit(4)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if wallpaper.isMissing {
                Label(
                    "Lumae remembers this wallpaper, but the media file is no longer available at its saved location.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    model.presentRelink(for: wallpaper)
                } label: {
                    Label("Locate File…", systemImage: "folder.badge.questionmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 10) {
                    Button {
                        model.revealInFinder(wallpaper)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        model.copyPath(wallpaper)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var destructiveSection: some View {
        InspectorSection(title: "Library") {
            Button(role: .destructive) {
                confirmRemoval = true
            } label: {
                Label("Remove from Lumae", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }

            Text("This removes only the library entry. Lumae never deletes the original media file.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if wallpaper.isMissing {
            Label("Missing", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.bold())
                .foregroundStyle(.red)
        } else {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption2.bold())
                .foregroundStyle(.green)
        }
    }


    private func beginRename() {
        draftName = wallpaper.name
        isRenaming = true
        DispatchQueue.main.async {
            nameFieldFocused = true
        }
    }

    private func cancelRename() {
        draftName = wallpaper.name
        isRenaming = false
        nameFieldFocused = false
    }

    private func commitRename() {
        guard model.rename(wallpaper, to: draftName) else { return }
        draftName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = false
        nameFieldFocused = false
    }

    private var byteCountFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }

    private func profileDescription(
        _ profile: VideoOptimizationProfile
    ) -> String {
        "Up to \(profile.maximumWidth) × \(profile.maximumHeight) at \(profile.maximumFrameRate) fps"
    }

    private func durationFormatter(_ duration: Double) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0
            ? String(format: "%d:%02d", minutes, seconds)
            : "\(seconds) sec"
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
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

private struct InspectorValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
