import SwiftUI
import AppKit
import LumaeCore

@MainActor
final class AppModel: ObservableObject {
    @Published var state = PersistedApplicationState()
    @Published var selectedWallpaperID: UUID?
    @Published var selectedDisplayID: String?
    @Published var searchText = ""
    @Published var sortOrder: LibrarySortOrder = .dateAddedNewest
    @Published var viewMode: LibraryViewMode = .grid
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isPaused = false
    @Published private(set) var displayTopology = DisplayTopology(displays: [])

    let store = JSONStateStore()
    let importer = WallpaperImporter()
    let displayService = DisplayDiscoveryService()
    let engine = WallpaperEngine()
    let cache = ThumbnailCache()
    let launchAtLogin = LaunchAtLoginService()

    private var configurationApplyTask: Task<Void, Never>?

    var filteredWallpapers: [WallpaperMetadata] {
        let filter = LibraryFilter(query: searchText)
        return WallpaperSorter.sort(
            state.wallpapers.filter(filter.matches),
            by: sortOrder
        )
    }

    var assignableWallpapers: [WallpaperMetadata] {
        state.wallpapers
            .filter { !$0.isMissing && $0.kind != .unsupported }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    init() {
        displayService.onTopologyChange = { [weak self] topology in
            Task { @MainActor in
                await self?.handleTopology(topology)
            }
        }

        Task { [weak self] in
            guard let self else { return }
            await self.load()
            self.displayService.start()
            self.reconcileAssignments(onto: self.displayService.currentTopology)
            if self.state.settings.restoreLastConfiguration {
                await self.engine.restore(
                    state: self.state,
                    topology: self.displayService.currentTopology
                )
            }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            state = try await store.load()
            state.wallpapers = state.wallpapers.map { item in
                var copy = item
                copy.isMissing = !FileManager.default.fileExists(
                    atPath: item.effectiveFilePath
                )
                return copy
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentImporter() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = WallpaperImporter.allowedTypes
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                await self?.importURLs(panel.urls)
            }
        }
    }

    func importURLs(_ urls: [URL]) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let imported = try await importer.importFiles(
                urls,
                behavior: state.settings.importBehavior,
                managedLibraryPath: state.settings.managedLibraryPath,
                existing: state.wallpapers,
                thumbnailCache: cache
            )
            state.wallpapers.append(contentsOf: imported)
            try await save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(_ wallpaper: WallpaperMetadata) {
        state.wallpapers.removeAll { $0.id == wallpaper.id }
        if selectedWallpaperID == wallpaper.id {
            selectedWallpaperID = nil
        }
        state.assignments = state.assignments.map {
            var copy = $0
            if copy.wallpaperID == wallpaper.id {
                copy.wallpaperID = nil
            }
            return copy
        }
        if state.sharedWallpaperID == wallpaper.id {
            state.sharedWallpaperID = nil
        }
        scheduleConfigurationApply()
    }


    func revealInFinder(_ wallpaper: WallpaperMetadata) {
        let url = URL(fileURLWithPath: wallpaper.effectiveFilePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "The wallpaper file is missing. Use Locate File… to reconnect it."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPath(_ wallpaper: WallpaperMetadata) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            wallpaper.effectiveFilePath,
            forType: .string
        )
    }

    func presentRelink(for wallpaper: WallpaperMetadata) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = WallpaperImporter.allowedTypes
        panel.prompt = "Relink"
        panel.message = "Choose the file that should replace the missing wallpaper reference."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.relink(wallpaper, to: url)
            }
        }
    }

    func relink(_ wallpaper: WallpaperMetadata, to url: URL) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let updated = try await importer.relink(
                wallpaper,
                to: url,
                existing: state.wallpapers,
                thumbnailCache: cache
            )
            guard let index = state.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else {
                return
            }
            state.wallpapers[index] = updated
            selectedWallpaperID = updated.id
            try await save()
            try await engine.applyConfiguration(
                state: state,
                topology: displayTopology
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ wallpaper: WallpaperMetadata) {
        guard let index = state.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else {
            return
        }
        state.wallpapers[index].isFavorite.toggle()
        persistSoon()
    }

    func applySelected() async {
        guard let id = selectedWallpaperID,
              let wallpaper = state.wallpapers.first(where: { $0.id == id }) else {
            return
        }
        await apply(wallpaper)
    }

    /// Applies a wallpaper from the library to the current presentation.
    /// In Per Display mode this intentionally assigns it to every active display;
    /// individual assignments are then refined from Display Layout.
    func apply(_ wallpaper: WallpaperMetadata) async {
        do {
            state.sharedWallpaperID = wallpaper.id
            reconcileAssignments(onto: displayService.currentTopology)

            if state.settings.presentationMode == .perDisplay {
                let activeIDs = displayService.currentTopology.activeDisplayIDs
                for index in state.assignments.indices
                    where activeIDs.contains(state.assignments[index].id) {
                    state.assignments[index].wallpaperID = wallpaper.id
                }
            }

            try await engine.applyConfiguration(
                state: state,
                topology: displayService.currentTopology
            )

            if let index = state.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
                state.wallpapers[index].dateLastUsed = Date()
            }
            try await save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPresentationMode(_ mode: DisplayPresentationMode) {
        guard state.settings.presentationMode != mode else { return }
        reconcileAssignments(onto: displayTopology)

        if mode != .perDisplay, state.sharedWallpaperID == nil {
            let mainDisplayID = displayTopology.displays.first(where: { $0.isMain })?.id
            let preferredAssignment = mainDisplayID.flatMap { displayID in
                state.assignments.first { $0.id == displayID }
            } ?? state.assignments.first(where: { $0.wallpaperID != nil })
            state.sharedWallpaperID = preferredAssignment?.wallpaperID
        }

        state.settings.presentationMode = mode
        scheduleConfigurationApply()
    }

    func setSharedWallpaper(_ wallpaperID: UUID?) {
        guard state.sharedWallpaperID != wallpaperID else { return }
        state.sharedWallpaperID = wallpaperID
        markWallpaperUsed(wallpaperID)
        scheduleConfigurationApply()
    }

    func setDefaultScalingMode(_ mode: WallpaperScalingMode) {
        guard state.settings.defaultScalingMode != mode else { return }
        state.settings.defaultScalingMode = mode
        scheduleConfigurationApply()
    }

    func setDisplayWallpaper(_ wallpaperID: UUID?, for displayID: String) {
        guard let index = assignmentIndex(for: displayID) else { return }
        guard state.assignments[index].wallpaperID != wallpaperID else { return }
        state.assignments[index].wallpaperID = wallpaperID
        markWallpaperUsed(wallpaperID)
        scheduleConfigurationApply()
    }

    func setDisplayEnabled(_ enabled: Bool, for displayID: String) {
        guard let index = assignmentIndex(for: displayID) else { return }
        guard state.assignments[index].enabled != enabled else { return }
        state.assignments[index].enabled = enabled
        scheduleConfigurationApply()
    }

    func setDisplayScalingMode(_ mode: WallpaperScalingMode, for displayID: String) {
        guard let index = assignmentIndex(for: displayID) else { return }
        guard state.assignments[index].scalingMode != mode else { return }
        state.assignments[index].scalingMode = mode
        scheduleConfigurationApply()
    }

    func applySharedWallpaperToAllDisplays() {
        reconcileAssignments(onto: displayTopology)
        let activeIDs = displayTopology.activeDisplayIDs
        for index in state.assignments.indices
            where activeIDs.contains(state.assignments[index].id) {
            state.assignments[index].wallpaperID = state.sharedWallpaperID
            state.assignments[index].enabled = true
        }
        scheduleConfigurationApply()
    }

    func displayAssignment(for display: DisplayDescriptor) -> DisplayAssignment {
        let restored = DisplayAssignmentRestorer.restore(
            saved: state.assignments,
            onto: displayTopology
        )
        return restored[display.id]
            ?? DisplayAssignment(
                displayFingerprint: display.fingerprint,
                wallpaperID: state.sharedWallpaperID,
                scalingMode: state.settings.defaultScalingMode
            )
    }

    func wallpaper(id: UUID?) -> WallpaperMetadata? {
        guard let id else { return nil }
        return state.wallpapers.first { $0.id == id }
    }

    func togglePause() {
        isPaused.toggle()
        isPaused ? engine.pause() : engine.resume()
    }

    func advancePlaylist() {
        var playlist = state.settings.playlist
        guard let id = PlaylistEngine.nextID(
            configuration: &playlist,
            availableIDs: Set(state.wallpapers.map(\.id))
        ) else {
            return
        }
        state.settings.playlist = playlist
        selectedWallpaperID = id
        Task { await applySelected() }
    }

    func handleTopology(_ topology: DisplayTopology) async {
        displayTopology = topology
        state.lastKnownTopology = topology
        reconcileAssignments(onto: topology)

        if selectedDisplayID == nil
            || !topology.activeDisplayIDs.contains(selectedDisplayID ?? "") {
            selectedDisplayID = topology.displays.first(where: { $0.isMain })?.id
                ?? topology.displays.first?.id
        }

        await engine.topologyDidChange(topology, state: state)
        persistSoon()
    }

    func save() async throws {
        try await store.save(state)
    }

    func persistSoon() {
        Task { try? await save() }
    }

    private func assignmentIndex(for displayID: String) -> Int? {
        reconcileAssignments(onto: displayTopology)
        return state.assignments.firstIndex { $0.id == displayID }
    }

    private func reconcileAssignments(onto topology: DisplayTopology) {
        guard !topology.displays.isEmpty else { return }

        let restored = DisplayAssignmentRestorer.restore(
            saved: state.assignments,
            onto: topology
        )

        let activeAssignments = topology.displays.map { display -> DisplayAssignment in
            var assignment = restored[display.id]
                ?? DisplayAssignment(
                    displayFingerprint: display.fingerprint,
                    wallpaperID: state.sharedWallpaperID
                        ?? state.wallpapers.first(where: { !$0.isMissing })?.id,
                    scalingMode: state.settings.defaultScalingMode
                )
            assignment.displayFingerprint = display.fingerprint
            return assignment
        }

        let disconnectedAssignments = state.assignments.filter { assignment in
            !topology.displays.contains { display in
                assignment.displayFingerprint.matchScore(
                    against: display.fingerprint
                ) >= 200
            }
        }

        state.assignments = activeAssignments + disconnectedAssignments
    }

    private func scheduleConfigurationApply() {
        configurationApplyTask?.cancel()
        configurationApplyTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            await self.applyCurrentConfiguration()
        }
    }

    private func applyCurrentConfiguration() async {
        do {
            try await save()
            try await engine.applyConfiguration(
                state: state,
                topology: displayTopology
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markWallpaperUsed(_ wallpaperID: UUID?) {
        guard let wallpaperID,
              let index = state.wallpapers.firstIndex(where: { $0.id == wallpaperID }) else {
            return
        }
        state.wallpapers[index].dateLastUsed = Date()
    }
}

enum LibraryViewMode: String, CaseIterable {
    case grid
    case list
}
