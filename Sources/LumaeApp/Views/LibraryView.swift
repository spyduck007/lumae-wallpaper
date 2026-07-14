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
                    Label("All Wallpapers", systemImage: "rectangle.grid.2x2").tag(SidebarSection.library)
                    Label("Favorites", systemImage: "star").tag(SidebarSection.favorites)
                    Label("Recently Used", systemImage: "clock").tag(SidebarSection.recent)
                    Label("Missing Files", systemImage: "exclamationmark.triangle").tag(SidebarSection.missing)
                }
                Section("Displays") { Label("Display Layout", systemImage: "display.2").tag(SidebarSection.displays) }
            }
            .navigationTitle("Lumae")
        } detail: {
            Group {
                if selectedSection == .displays { DisplayLayoutView() }
                else { libraryContent }
            }
            .navigationTitle(title)
            .toolbar { toolbar }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search names, tags, and categories")
        .dropDestination(for: URL.self) { urls, _ in Task { await model.importURLs(urls) }; return true } isTargeted: { isDropTargeted = $0 }
        .overlay { if isDropTargeted { RoundedRectangle(cornerRadius: 16).stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [8])).padding(16).background(.tint.opacity(0.08)) } }
        .alert("Lumae couldn’t complete that action", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "Unknown error") }
    }

    @ViewBuilder private var libraryContent: some View {
        let items = sectionItems
        if model.isLoading { ProgressView("Loading wallpaper library…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        else if items.isEmpty { ContentUnavailableView("No Wallpapers", systemImage: "photo.on.rectangle.angled", description: Text("Import JPG, PNG, HEIC, TIFF, GIF, MP4, MOV, or M4V files. Files stay local.")) .overlay(alignment: .bottom) { Button("Import Wallpapers…") { model.presentImporter() }.buttonStyle(.borderedProminent).padding(60) } }
        else if model.viewMode == .grid { WallpaperGrid(items: items) }
        else { WallpaperList(items: items) }
    }

    private var sectionItems: [WallpaperMetadata] {
        switch selectedSection { case .favorites: return model.filteredWallpapers.filter(\.isFavorite); case .recent: return model.filteredWallpapers.filter { $0.dateLastUsed != nil }; case .missing: return model.filteredWallpapers.filter(\.isMissing); default: return model.filteredWallpapers }
    }
    private var title: String { selectedSection?.title ?? "Library" }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Sort", selection: $model.sortOrder) { ForEach(LibrarySortOrder.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 150)
            Picker("View", selection: $model.viewMode) { Label("Grid", systemImage: "square.grid.2x2").tag(LibraryViewMode.grid); Label("List", systemImage: "list.bullet").tag(LibraryViewMode.list) }.pickerStyle(.segmented).labelsHidden().frame(width: 80)
            Button { model.presentImporter() } label: { Label("Import", systemImage: "plus") }
        }
    }
}

enum SidebarSection: Hashable { case library, favorites, recent, missing, displays
    var title: String { switch self { case .library: "All Wallpapers"; case .favorites: "Favorites"; case .recent: "Recently Used"; case .missing: "Missing Files"; case .displays: "Display Layout" } }
}

extension LibrarySortOrder { var label: String { switch self { case .dateAddedNewest: "Newest"; case .dateAddedOldest: "Oldest"; case .nameAscending: "Name A–Z"; case .nameDescending: "Name Z–A"; case .recentlyUsed: "Recently Used"; case .fileSize: "File Size" } } }
