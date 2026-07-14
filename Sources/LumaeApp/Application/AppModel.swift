import SwiftUI
import AppKit
import LumaeCore

@MainActor
final class AppModel: ObservableObject {
    @Published var state = PersistedApplicationState()
    @Published var selectedWallpaperID: UUID?
    @Published var searchText = ""
    @Published var sortOrder: LibrarySortOrder = .dateAddedNewest
    @Published var viewMode: LibraryViewMode = .grid
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isPaused = false
    @Published var isMenuBarVisible = true {
        didSet {
            guard isMenuBarVisible != state.settings.menuBarVisible else { return }
            state.settings.menuBarVisible = isMenuBarVisible
            persistSoon()
        }
    }

    let store = JSONStateStore()
    let importer = WallpaperImporter()
    let displayService = DisplayDiscoveryService()
    let engine = WallpaperEngine()
    let cache = ThumbnailCache()
    let launchAtLogin = LaunchAtLoginService()

    var filteredWallpapers: [WallpaperMetadata] {
        let filter = LibraryFilter(query: searchText)
        return WallpaperSorter.sort(state.wallpapers.filter(filter.matches), by: sortOrder)
    }

    init() {
        Task { await load() }
        displayService.onTopologyChange = { [weak self] topology in Task { @MainActor in await self?.handleTopology(topology) } }
        displayService.start()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            state = try await store.load()
            isMenuBarVisible = state.settings.menuBarVisible
            state.wallpapers = state.wallpapers.map { item in
                var copy = item; copy.isMissing = !FileManager.default.fileExists(atPath: item.effectiveFilePath); return copy
            }
            if state.settings.restoreLastConfiguration { await engine.restore(state: state, topology: displayService.currentTopology) }
        } catch { errorMessage = error.localizedDescription }
    }

    func presentImporter() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = WallpaperImporter.allowedTypes
        panel.begin { [weak self] response in guard response == .OK else { return }; Task { @MainActor in await self?.importURLs(panel.urls) } }
    }

    func importURLs(_ urls: [URL]) async {
        isLoading = true; defer { isLoading = false }
        do {
            let imported = try await importer.importFiles(urls, behavior: state.settings.importBehavior,
                managedLibraryPath: state.settings.managedLibraryPath, existing: state.wallpapers, thumbnailCache: cache)
            state.wallpapers.append(contentsOf: imported); try await save()
        } catch { errorMessage = error.localizedDescription }
    }

    func remove(_ wallpaper: WallpaperMetadata) {
        state.wallpapers.removeAll { $0.id == wallpaper.id }
        state.assignments = state.assignments.map { var copy = $0; if copy.wallpaperID == wallpaper.id { copy.wallpaperID = nil }; return copy }
        persistSoon()
    }

    func toggleFavorite(_ wallpaper: WallpaperMetadata) {
        guard let index = state.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        state.wallpapers[index].isFavorite.toggle(); persistSoon()
    }

    func applySelected() async {
        guard let id = selectedWallpaperID, let wallpaper = state.wallpapers.first(where: { $0.id == id }) else { return }
        await apply(wallpaper)
    }

    func apply(_ wallpaper: WallpaperMetadata) async {
        do {
            state.sharedWallpaperID = wallpaper.id
            if state.settings.presentationMode == .perDisplay {
                state.assignments = displayService.currentTopology.displays.map {
                    DisplayAssignment(displayFingerprint: $0.fingerprint, wallpaperID: wallpaper.id, scalingMode: state.settings.defaultScalingMode)
                }
            }
            try await engine.apply(wallpaper: wallpaper, state: state, topology: displayService.currentTopology)
            if let index = state.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) { state.wallpapers[index].dateLastUsed = Date() }
            try await save()
        } catch { errorMessage = error.localizedDescription }
    }

    func togglePause() { isPaused.toggle(); isPaused ? engine.pause() : engine.resume() }
    func advancePlaylist() {
        var playlist = state.settings.playlist
        guard let id = PlaylistEngine.nextID(configuration: &playlist, availableIDs: Set(state.wallpapers.map(\.id))) else { return }
        state.settings.playlist = playlist; selectedWallpaperID = id; Task { await applySelected() }
    }
    func handleTopology(_ topology: DisplayTopology) async { state.lastKnownTopology = topology; await engine.topologyDidChange(topology, state: state); persistSoon() }
    func save() async throws { try await store.save(state) }
    func persistSoon() { Task { try? await save() } }
}

enum LibraryViewMode: String, CaseIterable { case grid, list }
