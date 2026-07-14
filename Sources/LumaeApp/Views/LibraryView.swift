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
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            if selectedSection == .displays {
                DisplayLayoutView()
                    .navigationTitle(title)
            } else {
                libraryContent
                    .navigationTitle(title)
                    .toolbar { libraryToolbar }
                    .searchable(
                        text: $model.searchText,
                        placement: .toolbar,
                        prompt: "Search wallpapers"
                    )
            }
        }
        .dropDestination(for: URL.self) { urls, _ in Task { await model.importURLs(urls) }; return true } isTargeted: { isDropTargeted = $0 }
        .overlay { if isDropTargeted { RoundedRectangle(cornerRadius: 16).stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [8])).padding(16).background(.tint.opacity(0.08)) } }
        .alert("Lumae couldn’t complete that action", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "Unknown error") }
    }

    @ViewBuilder private var libraryContent: some View {
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
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No Wallpapers")
                    .font(.title2.bold())
                Text("Import JPG, PNG, HEIC, TIFF, GIF, MP4, MOV, or M4V files. Your files stay local.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                Button("Import Wallpapers…") { model.presentImporter() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.viewMode == .grid { WallpaperGrid(items: items) }
        else { WallpaperList(items: items) }
    }

    private var sectionItems: [WallpaperMetadata] {
        switch selectedSection { case .favorites: return model.filteredWallpapers.filter(\.isFavorite); case .recent: return model.filteredWallpapers.filter { $0.dateLastUsed != nil }; case .missing: return model.filteredWallpapers.filter(\.isMissing); default: return model.filteredWallpapers }
    }
    private var title: String { selectedSection?.title ?? "Library" }

    @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
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

            Button { model.presentImporter() } label: {
                Label("Import Wallpapers", systemImage: "plus")
            }
            .help("Import wallpapers")
        }
    }
}

enum SidebarSection: Hashable { case library, favorites, recent, missing, displays
    var title: String { switch self { case .library: "All Wallpapers"; case .favorites: "Favorites"; case .recent: "Recently Used"; case .missing: "Missing Files"; case .displays: "Display Layout" } }
}

extension LibrarySortOrder { var label: String { switch self { case .dateAddedNewest: "Newest"; case .dateAddedOldest: "Oldest"; case .nameAscending: "Name A–Z"; case .nameDescending: "Name Z–A"; case .recentlyUsed: "Recently Used"; case .fileSize: "File Size" } } }
