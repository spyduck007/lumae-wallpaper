import SwiftUI
import UniformTypeIdentifiers
import LumaeCore

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedSection: SidebarSection? = .library
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Library") {
                    Label("All Wallpapers", systemImage: "rectangle.grid.2x2")
                        .tag(SidebarSection.library)
                    Label("Favorites", systemImage: "star")
                        .tag(SidebarSection.favorites)
                    Label("Recently Used", systemImage: "clock")
                        .tag(SidebarSection.recent)
                    Label("Missing Files", systemImage: "exclamationmark.triangle")
                        .tag(SidebarSection.missing)
                }

                Section("Playlists") {
                    ForEach(model.playlists) { playlist in
                        HStack(spacing: 8) {
                            Label(playlist.name, systemImage: "music.note.list")
                                .lineLimit(1)
                            Spacer()
                            if model.state.activePlaylistID == playlist.id {
                                Circle()
                                    .fill(playlist.isRunning ? Color.green : Color.orange)
                                    .frame(width: 7, height: 7)
                                    .accessibilityLabel(playlist.isRunning ? "Playing" : "Paused")
                            }
                        }
                        .tag(SidebarSection.playlist(playlist.id))
                    }

                    Button {
                        let id = model.createPlaylist()
                        selectedSection = .playlist(id)
                    } label: {
                        Label("New Playlist", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                }

                Section("Desktop") {
                    Label("Widgets", systemImage: "square.stack.3d.up")
                        .tag(SidebarSection.widgets)
                    Label("Display Layout", systemImage: "display.2")
                        .tag(SidebarSection.displays)
                }
            }
            .navigationTitle("Lumae")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            switch selectedSection {
            case .widgets:
                WidgetsView()
                    .navigationTitle(title)

            case .displays:
                DisplayLayoutView()
                    .navigationTitle(title)

            case .playlist(let id):
                PlaylistView(
                    playlistID: id,
                    onDelete: { selectedSection = .library }
                )
                .navigationTitle(title)

            default:
                libraryDetail
                    .navigationTitle(title)
                    .toolbar { libraryToolbar }
                    .searchable(
                        text: $model.searchText,
                        placement: .toolbar,
                        prompt: "Search wallpapers"
                    )
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.importURLs(urls) }
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(16)
                    .background(.tint.opacity(0.08))
            }
        }
        .alert(
            "Lumae couldn’t complete that action",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var libraryDetail: some View {
        HStack(spacing: 0) {
            libraryContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let selectedWallpaper {
                Divider()

                WallpaperInspectorView(
                    wallpaper: selectedWallpaper,
                    openDisplayLayout: {
                        selectedSection = .displays
                    }
                )
                .frame(width: 350)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: selectedWallpaper?.id)
    }

    @ViewBuilder
    private var libraryContent: some View {
        let items = sectionItems

        if model.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading wallpaper library…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: selectedSection == .missing
                    ? "checkmark.circle"
                    : "photo.on.rectangle.angled")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(emptyTitle)
                    .font(.title2.bold())

                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)

                if selectedSection != .missing {
                    Button("Import Wallpapers…") {
                        model.presentImporter()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.viewMode == .grid {
            WallpaperGrid(items: items)
        } else {
            WallpaperList(items: items)
        }
    }

    private var sectionItems: [WallpaperMetadata] {
        switch selectedSection {
        case .favorites:
            return model.filteredWallpapers.filter(\.isFavorite)
        case .recent:
            return model.filteredWallpapers.filter { $0.dateLastUsed != nil }
        case .missing:
            return model.filteredWallpapers.filter(\.isMissing)
        default:
            return model.filteredWallpapers
        }
    }

    private var selectedWallpaper: WallpaperMetadata? {
        guard let id = model.selectedWallpaperID else { return nil }
        return sectionItems.first { $0.id == id }
    }

    private var title: String {
        if case .playlist(let id) = selectedSection,
           let playlist = model.playlist(id: id) {
            return playlist.name
        }
        return selectedSection?.title ?? "Library"
    }

    private var emptyTitle: String {
        switch selectedSection {
        case .favorites: return "No Favorites"
        case .recent: return "Nothing Used Yet"
        case .missing: return "No Missing Files"
        default: return "No Wallpapers"
        }
    }

    private var emptyMessage: String {
        switch selectedSection {
        case .favorites:
            return "Favorite a wallpaper from its card or inspector to keep it here."
        case .recent:
            return "Wallpapers appear here after you apply them."
        case .missing:
            return "Every wallpaper file in your library is currently available."
        default:
            return "Import JPG, PNG, HEIC, TIFF, GIF, MP4, MOV, or M4V files. Your files stay local."
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                    Button {
                        model.sortOrder = order
                    } label: {
                        if model.sortOrder == order {
                            Label(order.label, systemImage: "checkmark")
                        } else {
                            Text(order.label)
                        }
                    }
                }
            } label: {
                Label(model.sortOrder.label, systemImage: "arrow.up.arrow.down")
            }
            .help("Sort wallpapers")

            Picker("View", selection: $model.viewMode) {
                Label("Grid", systemImage: "square.grid.2x2")
                    .tag(LibraryViewMode.grid)
                Label("List", systemImage: "list.bullet")
                    .tag(LibraryViewMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 82)
            .help("Change library view")

            Button {
                model.presentImporter()
            } label: {
                Label("Import Wallpapers", systemImage: "plus")
            }
            .help("Import wallpapers")
        }
    }
}

enum SidebarSection: Hashable {
    case library
    case favorites
    case recent
    case missing
    case playlist(UUID)
    case widgets
    case displays

    var title: String {
        switch self {
        case .library: return "All Wallpapers"
        case .favorites: return "Favorites"
        case .recent: return "Recently Used"
        case .missing: return "Missing Files"
        case .playlist: return "Playlist"
        case .widgets: return "Widgets"
        case .displays: return "Display Layout"
        }
    }
}

extension LibrarySortOrder {
    var label: String {
        switch self {
        case .dateAddedNewest: return "Newest"
        case .dateAddedOldest: return "Oldest"
        case .nameAscending: return "Name A–Z"
        case .nameDescending: return "Name Z–A"
        case .recentlyUsed: return "Recently Used"
        case .fileSize: return "File Size"
        }
    }
}
